#!/usr/bin/env bash
#
# Battery module for waybar, plus the CPU power-mode indicator colour.
#
# Three modes:
#   (no args)  emit the waybar module JSON — glyph and capacity, no tooltip
#   menu       open the system stats as a rofi dropdown under the battery
#              (click again or Esc to close)
#   rows       rofi script-mode backend; rofi re-execs this on every keypress
#              it is told to act on, which is how the panel refreshes
#
# Why script mode and not -dmenu: rofi has no refresh timer and no IPC, so a
# dmenu panel can only update by exiting and being relaunched — a measured 58ms
# window teardown every time. In script mode rofi re-runs this script itself and
# repaints the existing window, so Return/r/space update the numbers in place
# with no flicker and no lost cursor position (\0keep-selection).
#
# The class (mode-performance / mode-battery / mode-normal) is what style.css
# uses to tint the glyph red / green / white. See performance-mode.sh.
#
# Stats notes:
#   * CPU load and Intel GPU busy are rate counters, so they are diffed against
#     the previous sample cached in STATE_FILE. The dropdown is the only reader
#     now, so a first open (or one more than 30s after the last) takes a short
#     inline sample instead; each in-place refresh diffs against the sample the
#     previous repaint left behind, which is what makes the deltas meaningful.
#   * The NVIDIA card is only queried while awake: nvidia-smi on a
#     runtime-suspended dGPU spins it up and eats battery.
#   * Nerd Font glyphs are built with $'\uXXXX' escapes rather than pasted in
#     literally — PUA codepoints do not survive every editor/pipeline
#     round-trip, and a silently emptied glyph is invisible to review.

# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../scripts" && pwd)/_paths.sh"

MODE_FILE=/tmp/waybar-performance-mode
BAT=/sys/class/power_supply/BAT0
STATE_FILE="/tmp/waybar-sysstats-$(id -u)"
STATE_MAX_AGE_NS=30000000000        # 30s; an older sample gives a bogus rate
THEME="${HYPR_ROFI}/sysstats.rasi"

# Tokyonight accents, matching the rest of the bar.
DIM='#6f7488'
GREEN='#9ece6a'
AMBER='#e0af68'
RED='#f7768e'

ACTION=${1-}

# Toggle before doing any work: a second click closes the open panel.
if [ "$ACTION" = menu ]; then
  if pgrep -f "rofi.*apps/rofi/sysstats.rasi" >/dev/null 2>&1; then
    pkill -f "rofi.*apps/rofi/sysstats.rasi" >/dev/null 2>&1 || true
    exit 0
  fi
fi

# ── samplers ─────────────────────────────────────────────────────────────────

cpu_sample() {   # -> "busy total" in jiffies
  awk '/^cpu /{ t=0; for (i=2; i<=NF; i++) t+=$i; print t-($5+$6), t; exit }' /proc/stat
}

# Per-engine i915 busy nanoseconds, summed over every DRM client we can read
# (fdinfo is only readable for our own processes — which is every GPU client
# that matters here). find picks out just the /dev/dri fds, which is half the
# cost of grepping every fdinfo file; grep then reads them, tolerating the ones
# that vanish mid-scan (awk would abort on those).
igpu_sample() {  # -> "engine=ns engine=ns ..."
  find /proc/[0-9]*/fd -lname '/dev/dri/*' 2>/dev/null \
    | sed 's#/fd/#/fdinfo/#' | tr '\n' '\0' \
    | xargs -0 -r grep -sH -E '^drm-(driver|client-id|engine-)' 2>/dev/null | awk '
    { i = index($0, ":"); f = substr($0, 1, i-1); rest = substr($0, i+1)
      j = index(rest, ":"); key = substr(rest, 1, j-1); val = substr(rest, j+1)
      gsub(/^[ \t]+/, "", val)
      if (key == "drm-driver")         drv[f] = val
      else if (key == "drm-client-id") cid[f] = val
      else if (key ~ /^drm-engine-/)   { ev[f "|" key] = val + 0 } }
    END {
      for (fk in ev) {
        split(fk, p, "|"); f = p[1]; k = p[2]
        if (drv[f] != "i915") continue
        # One client can hold several fds carrying identical counters.
        if (seen[cid[f] "|" k]++) continue
        eng[substr(k, 12)] += ev[fk]
      }
      for (e in eng) printf "%s=%d ", e, eng[e]
    }'
}

# CPU package temperature. Also the best iGPU reading available: the Alder Lake
# GT1 shares the die and exposes no hwmon of its own.
pkg_temp() {
  local h label
  for h in /sys/class/hwmon/hwmon*; do
    [ "$(cat "$h/name" 2>/dev/null)" = coretemp ] || continue
    for label in "$h"/temp*_label; do
      case "$(cat "$label" 2>/dev/null)" in
        Package*) awk '{ printf "%.0f", $1/1000 }' "${label%_label}_input" 2>/dev/null; return ;;
      esac
    done
  done
  awk '{ printf "%.0f", $1/1000 }' /sys/class/thermal/thermal_zone0/temp 2>/dev/null
}

read_state() {
  [ -r "$STATE_FILE" ] || return 1
  { read -r prev_t prev_busy prev_total; read -r prev_eng; } < "$STATE_FILE"
  [ -n "$prev_t" ] || return 1
  [ "$(( now - prev_t ))" -gt 0 ] && [ "$(( now - prev_t ))" -le "$STATE_MAX_AGE_NS" ]
}

# ── collect: fills cpu_pct / igpu_pct / mem_* / sw_* / pkg / nv_* ─────────────

collect() {
  now=$(date +%s%N)
  read -r cpu_busy cpu_total < <(cpu_sample)
  eng_now=$(igpu_sample)

  if ! read_state; then
    # First run, or a long gap: take a quick inline sample instead of guessing.
    prev_t=$now; prev_busy=$cpu_busy; prev_total=$cpu_total; prev_eng=$eng_now
    sleep 0.2
    now=$(date +%s%N)
    read -r cpu_busy cpu_total < <(cpu_sample)
    eng_now=$(igpu_sample)
  fi

  # Leave a baseline behind so a Return-refresh (or the next open) has a real
  # interval to diff against instead of paying for another inline sample.
  printf '%s %s %s\n%s\n' "$now" "$cpu_busy" "$cpu_total" "$eng_now" > "$STATE_FILE"

  elapsed_ns=$(( now - prev_t ))
  d_busy=$(( cpu_busy - prev_busy ))
  d_total=$(( cpu_total - prev_total ))
  if [ "$d_total" -gt 0 ]; then
    cpu_pct=$(awk -v b="$d_busy" -v t="$d_total" 'BEGIN{ p=b/t*100; printf "%.0f", (p<0?0:(p>100?100:p)) }')
  else
    cpu_pct=''
  fi

  # Busiest engine rather than the sum, so parallel engines cannot exceed 100%.
  igpu_pct=$(awk -v prev="$prev_eng" -v cur="$eng_now" -v el="$elapsed_ns" 'BEGIN{
    if (el <= 0) exit
    n = split(prev, a, " "); for (i = 1; i <= n; i++) { split(a[i], kv, "="); was[kv[1]] = kv[2] }
    n = split(cur, a, " "); best = -1
    for (i = 1; i <= n; i++) {
      split(a[i], kv, "=")
      if (!(kv[1] in was)) continue          # client appeared after the last poll
      d = kv[2] - was[kv[1]]
      if (d > best) best = d
    }
    if (best < 0) exit
    p = best / el * 100
    printf "%.0f", (p < 0 ? 0 : (p > 100 ? 100 : p))
  }')

  read -r mem_pct mem_used_g mem_total_g sw_pct sw_used_g sw_total_g < <(awk '
    /^MemTotal:/     { mt = $2 }
    /^MemAvailable:/ { ma = $2 }
    /^SwapTotal:/    { st = $2 }
    /^SwapFree:/     { sf = $2 }
    END {
      mu = mt - ma; su = st - sf
      printf "%.0f %.1f %.0f %s %.1f %.0f\n",
        (mt ? mu/mt*100 : 0), mu/1048576, mt/1048576,
        (st ? sprintf("%.0f", su/st*100) : "-"), su/1048576, st/1048576
    }' /proc/meminfo)
  sw_pct=${sw_pct#-}

  pkg=$(pkg_temp)

  nv_pct=''; nv_temp=''; nv_note=''; nv_present=0
  local card nv_dev nv_out nv_used nv_total
  for card in /sys/class/drm/card*/device; do
    grep -q 'DRIVER=nvidia' "$card/uevent" 2>/dev/null || continue
    nv_present=1
    nv_dev=$(readlink -f "$card")
    if [ "$(cat "$nv_dev/power/runtime_status" 2>/dev/null)" = suspended ]; then
      nv_note='asleep'              # do not poke it — a query wakes the card
    elif nv_out=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total \
                    --format=csv,noheader,nounits 2>/dev/null | head -1); then
      IFS=', ' read -r nv_pct nv_temp nv_used nv_total <<< "$nv_out"
      # Any field can come back as [N/A] (e.g. in some Optimus states) — drop
      # non-numeric values so the integer comparisons below stay safe.
      [[ $nv_pct  =~ ^[0-9]+$ ]] || nv_pct=''
      [[ $nv_temp =~ ^[0-9]+$ ]] || nv_temp=''
      nv_note=$(awk -v u="$nv_used" -v t="$nv_total" 'BEGIN{ if (t+0 > 0) printf "%.1f/%.0fG", u/1024, t/1024 }')
    else
      nv_note='n/a'
    fi
    break
  done
}

# ── row rendering (shared by the tooltip and the dropdown) ────────────────────

pct_color() {
  if   [ -z "$1" ];        then echo "$DIM"
  elif [ "$1" -ge 85 ];    then echo "$RED"
  elif [ "$1" -ge 60 ];    then echo "$AMBER"
  else                          echo "$GREEN"; fi
}

temp_cell() {
  [ -z "$1" ] && { printf '<span color="%s">   --</span>' "$DIM"; return; }
  local c="$GREEN"
  [ "$1" -ge 70 ] && c="$AMBER"
  [ "$1" -ge 85 ] && c="$RED"
  printf '<span color="%s">%3d°C</span>' "$c" "$1"
}

meter() {       # 10-cell bar, monospace-safe
  local pct=$1 filled i out=''
  [ -z "$pct" ] && { printf '<span color="%s">··········</span>' "$DIM"; return; }
  filled=$(( (pct * 10 + 50) / 100 ))
  for ((i = 0; i < filled; i++)); do out+='█'; done
  printf '<span color="%s">%s</span><span color="%s">' "$(pct_color "$pct")" "$out" "$DIM"
  for ((i = filled; i < 10; i++)); do printf '░'; done
  printf '</span>'
}

row() {         # label, percent, trailing cell
  local label=$1 pct=$2 tail=$3 shown='  --'
  [ -n "$pct" ] && shown=$(printf '%4d' "$pct")
  printf '<span color="%s">%-5s</span> %s <span color="%s">%s%%</span>  %s' \
    "$DIM" "$label" "$(meter "$pct")" "$(pct_color "$pct")" "$shown" "$tail"
}

dim() { printf '<span color="%s">%s</span>' "$DIM" "$1"; }

stat_rows() {   # one markup row per line
  row CPU  "$cpu_pct"  "$(temp_cell "$pkg")"
  echo
  row RAM  "$mem_pct"  "$(dim "${mem_used_g}/${mem_total_g}G")"
  echo
  row SWAP "$sw_pct"   "$(dim "${sw_used_g}/${sw_total_g}G")"
  echo
  row GPU0 "$igpu_pct" "$(temp_cell "$pkg") $(dim 'Intel UHD')"
  echo
  if [ "$nv_present" = 1 ]; then
    local tail='RTX 3050'
    [ -n "$nv_note" ] && tail+=" · $nv_note"
    row GPU1 "$nv_pct" "$(temp_cell "$nv_temp") $(dim "$tail")"
    echo
  fi
}

# ── battery ──────────────────────────────────────────────────────────────────

# Health = present full-charge capacity vs the factory design capacity, i.e.
# how much of the original battery is left. upower reports it directly (13ms,
# cheap enough for the 5s poll); the sysfs arithmetic below is the identical
# number, kept for when upower isn't installed.
battery_health() {
  local dev pct=''
  if command -v upower >/dev/null 2>&1; then
    dev=$(upower -e 2>/dev/null | grep -m1 BAT)
    [ -n "$dev" ] && pct=$(upower -i "$dev" 2>/dev/null | awk '/capacity:/ { print $2 }')
  fi
  if [ -z "$pct" ]; then
    pct=$(awk -v f="$(cat "$BAT/energy_full" 2>/dev/null)" \
              -v d="$(cat "$BAT/energy_full_design" 2>/dev/null)" \
              'BEGIN{ if (d+0 > 0) print f/d*100 }')
  fi
  pct=${pct%\%}
  if [ -n "$pct" ]; then printf '%.0f%%' "$pct"; else printf 'n/a'; fi
}

read_battery() {
  mode=$(cat "$MODE_FILE" 2>/dev/null || echo normal)
  case "$mode" in
    performance) mode_label='Performance' ;;
    battery)     mode_label='Battery saver' ;;
    normal)      mode_label='Balanced' ;;
    *)           mode=normal; mode_label='Balanced' ;;
  esac

  if [ -d "$BAT" ]; then
    status=$(cat "$BAT/status" 2>/dev/null || echo Unknown)
    capacity=$(cat "$BAT/capacity" 2>/dev/null || echo 0)
    health=$(battery_health)

    if   [ "$capacity" -gt 80 ]; then icon=$''
    elif [ "$capacity" -gt 40 ]; then icon=$''
    elif [ "$capacity" -gt 15 ]; then icon=$''
    else                              icon=$''
    fi

    # Charging bolt while plugged in.
    case "$status" in
      Charging|Full) bolt=$' ' ;;
      *)             bolt='' ;;
    esac

    text="${bolt}${icon} ${capacity}%"
    head_plain="${icon} ${capacity}%  ·  ${status} · ${mode_label} · health ${health}"
    head_markup=$(printf '<span size="large">%s %s%%</span>  %s' \
      "$icon" "$capacity" "$(dim "${status} · ${mode_label} · health ${health}")")
  else
    text=$' AC'
    head_plain="$(printf '') AC  ·  ${mode_label}"
    head_markup=$(printf '<span size="large">%s AC</span>  %s' \
      $'' "$(dim "No battery · ${mode_label}")")
  fi
}

# ── output ───────────────────────────────────────────────────────────────────

# rofi script-mode backend. Rofi execs us with ROFI_RETV=0 for the first paint
# and 1 when a row is "selected" (Return, or a click) — both just re-render, so
# every such keypress is a live refresh of the same window.
if [ "$ACTION" = rows ]; then
  collect
  read_battery
  # Header/footer are reset on each pass so the battery line and prompt stay
  # current too, not just the table.
  printf '\0prompt\x1f%s\n' "$head_plain"
  printf '\0markup-rows\x1ftrue\n'
  printf '\0no-custom\x1ftrue\n'
  printf '\0keep-selection\x1ftrue\n'
  # The rows are deliberately left selectable even though nothing "opens": a
  # nonselectable row cannot be activated, which would make Return a no-op and
  # kill the refresh. The theme suppresses the highlight instead, so the panel
  # still reads as a table rather than a menu. The hint lives in the theme
  # footer, so no \0message (and no message widget in the theme) is needed.
  stat_rows
  exit 0
fi

if [ "$ACTION" = menu ]; then
  # Esc closes (kb-cancel, untouched). 'r' and space are wired to the same
  # re-render as Return via kb-accept-entry, so any of them refreshes in place.
  exec rofi -show stats -modi "stats:$0 rows" -theme "$THEME" \
    -kb-accept-entry 'Return,KP_Enter,r,space'
fi

# Bar module: battery only. The stats live in the click dropdown, so the poll
# skips collect() entirely — no /proc/*/fdinfo walk, no nvidia-smi, and the
# rate-counter cache is left to the panel to sample for itself.
read_battery

jq -nc --arg t "$text" --arg c "mode-$mode" \
  '{text:$t, tooltip:"", class:$c}'
