#!/usr/bin/env bash
# domain/sysstats.sh — CPU, GPU, memory and temperature sampling.
#
# CPU utilisation and Intel GPU busy time are *rate* counters: a single read
# is meaningless, and a percentage only exists relative to a previous
# sample. That baseline is cached, so each repaint diffs against the sample
# the previous repaint left behind and costs nothing extra; only a first
# open (or one after a long gap) pays for a short inline sample.
#
# Separated from the rendering so the numbers can be tested without a
# terminal and reused by anything that wants them.

hypr::use core/guard core/paths os/proc os/state

readonly SYSSTATS_CACHE="${HYPR_RUN_DIR}/sysstats"
readonly SYSSTATS_MAX_AGE_NS=30000000000   # 30s; older gives a bogus rate
readonly SYSSTATS_INLINE_SAMPLE=0.2

# Results are published as these globals rather than returned, because bash
# cannot return a record and the alternative (one subshell per field) would
# re-sample the hardware for each one.
declare -g SYS_CPU_PCT='' SYS_IGPU_PCT='' SYS_PKG_TEMP=''
declare -g SYS_MEM_PCT='' SYS_MEM_USED='' SYS_MEM_TOTAL=''
declare -g SYS_SWAP_PCT='' SYS_SWAP_USED='' SYS_SWAP_TOTAL=''
declare -g SYS_NV_PRESENT=0 SYS_NV_PCT='' SYS_NV_TEMP='' SYS_NV_NOTE=''

# ---------------------------------------------------------------------------
# Raw samplers
# ---------------------------------------------------------------------------
sysstats::_cpu_sample() {   # -> "busy total", in jiffies
  awk '/^cpu /{ t = 0; for (i = 2; i <= NF; i++) t += $i; print t - ($5 + $6), t; exit }' /proc/stat
}

# Per-engine i915 busy nanoseconds, summed over every DRM client we can read.
# fdinfo is only readable for our own processes, which is every GPU client
# that matters here. `find` picks out just the /dev/dri fds — half the cost
# of grepping every fdinfo — and grep tolerates the ones that vanish
# mid-scan, which awk would abort on.
sysstats::_igpu_sample() {  # -> "engine=ns engine=ns ..."
  find /proc/[0-9]*/fd -lname '/dev/dri/*' 2>/dev/null \
    | sed 's#/fd/#/fdinfo/#' | tr '\n' '\0' \
    | xargs -0 -r grep -sH -E '^drm-(driver|client-id|engine-)' 2>/dev/null | awk '
    { i = index($0, ":"); f = substr($0, 1, i - 1); rest = substr($0, i + 1)
      j = index(rest, ":"); key = substr(rest, 1, j - 1); val = substr(rest, j + 1)
      gsub(/^[ \t]+/, "", val)
      if (key == "drm-driver")         drv[f] = val
      else if (key == "drm-client-id") cid[f] = val
      else if (key ~ /^drm-engine-/)   ev[f "|" key] = val + 0 }
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

# CPU package temperature — also the best iGPU reading available, since the
# Alder Lake GT1 shares the die and exposes no hwmon of its own.
sysstats::_package_temp() {
  local hwmon label
  for hwmon in /sys/class/hwmon/hwmon*; do
    [[ $(proc::capture_or '' cat "$hwmon/name") == coretemp ]] || continue
    for label in "$hwmon"/temp*_label; do
      case "$(proc::capture_or '' cat "$label")" in
        Package*)
          awk '{ printf "%.0f", $1 / 1000 }' "${label%_label}_input" 2>/dev/null
          return 0 ;;
      esac
    done
  done
  awk '{ printf "%.0f", $1 / 1000 }' /sys/class/thermal/thermal_zone0/temp 2>/dev/null
}

sysstats::_memory() {
  awk '
    /^MemTotal:/     { mt = $2 }
    /^MemAvailable:/ { ma = $2 }
    /^SwapTotal:/    { st = $2 }
    /^SwapFree:/     { sf = $2 }
    END {
      mu = mt - ma; su = st - sf
      printf "%.0f %.1f %.0f %s %.1f %.0f\n",
        (mt ? mu / mt * 100 : 0), mu / 1048576, mt / 1048576,
        (st ? sprintf("%.0f", su / st * 100) : "0"), su / 1048576, st / 1048576
    }' /proc/meminfo
}

# The discrete NVIDIA card, queried only while it is awake: nvidia-smi on a
# runtime-suspended dGPU spins it up and costs real battery.
sysstats::_nvidia() {
  local card device output used total
  SYS_NV_PRESENT=0; SYS_NV_PCT=''; SYS_NV_TEMP=''; SYS_NV_NOTE=''
  for card in /sys/class/drm/card*/device; do
    grep -q 'DRIVER=nvidia' "$card/uevent" 2>/dev/null || continue
    SYS_NV_PRESENT=1
    device=$(readlink -f "$card")
    if [[ $(proc::capture_or '' cat "$device/power/runtime_status") == suspended ]]; then
      SYS_NV_NOTE=asleep
    elif guard::has nvidia-smi && output=$(proc::capture nvidia-smi \
          --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total \
          --format=csv,noheader,nounits); then
      IFS=', ' read -r SYS_NV_PCT SYS_NV_TEMP used total <<<"$(head -1 <<<"$output")"
      # Any field can come back as [N/A] in some Optimus states; drop
      # non-numeric values so later integer comparisons stay safe.
      [[ $SYS_NV_PCT  =~ ^[0-9]+$ ]] || SYS_NV_PCT=''
      [[ $SYS_NV_TEMP =~ ^[0-9]+$ ]] || SYS_NV_TEMP=''
      SYS_NV_NOTE=$(awk -v u="$used" -v t="$total" \
        'BEGIN { if (t + 0 > 0) printf "%.1f/%.0fG", u / 1024, t / 1024 }')
    else
      SYS_NV_NOTE=n/a
    fi
    break
  done
}

# ---------------------------------------------------------------------------
# Rate baseline
# ---------------------------------------------------------------------------
sysstats::_read_baseline() {
  [[ -r $SYSSTATS_CACHE ]] || return 1
  { read -r _prev_t _prev_busy _prev_total; read -r _prev_eng; } <"$SYSSTATS_CACHE"
  [[ -n ${_prev_t:-} ]] || return 1
  local age=$(( _now - _prev_t ))
  (( age > 0 && age <= SYSSTATS_MAX_AGE_NS ))
}

sysstats::_write_baseline() {
  mkdir -p -- "$HYPR_RUN_DIR"
  printf '%s %s %s\n%s\n' "$_now" "$_cpu_busy" "$_cpu_total" "$_eng_now" >"$SYSSTATS_CACHE"
}

# ---------------------------------------------------------------------------
# sysstats::collect — fill every SYS_* global.
# ---------------------------------------------------------------------------
sysstats::collect() {
  local _now _cpu_busy _cpu_total _eng_now _prev_t _prev_busy _prev_total _prev_eng
  local elapsed d_busy d_total

  _now=$(date +%s%N)
  read -r _cpu_busy _cpu_total < <(sysstats::_cpu_sample)
  _eng_now=$(sysstats::_igpu_sample)

  if ! sysstats::_read_baseline; then
    # First run or a long gap: take a short inline sample rather than guess.
    _prev_t=$_now; _prev_busy=$_cpu_busy; _prev_total=$_cpu_total; _prev_eng=$_eng_now
    sleep "$SYSSTATS_INLINE_SAMPLE"
    _now=$(date +%s%N)
    read -r _cpu_busy _cpu_total < <(sysstats::_cpu_sample)
    _eng_now=$(sysstats::_igpu_sample)
  fi

  sysstats::_write_baseline

  elapsed=$(( _now - _prev_t ))
  d_busy=$(( _cpu_busy - _prev_busy ))
  d_total=$(( _cpu_total - _prev_total ))
  if (( d_total > 0 )); then
    SYS_CPU_PCT=$(awk -v b="$d_busy" -v t="$d_total" \
      'BEGIN { p = b / t * 100; printf "%.0f", (p < 0 ? 0 : (p > 100 ? 100 : p)) }')
  else
    SYS_CPU_PCT=''
  fi

  # Busiest engine rather than the sum: engines run in parallel, so summing
  # them can exceed 100% and read as nonsense.
  SYS_IGPU_PCT=$(awk -v prev="$_prev_eng" -v cur="$_eng_now" -v el="$elapsed" 'BEGIN {
    if (el <= 0) exit
    n = split(prev, a, " "); for (i = 1; i <= n; i++) { split(a[i], kv, "="); was[kv[1]] = kv[2] }
    n = split(cur, a, " "); best = -1
    for (i = 1; i <= n; i++) {
      split(a[i], kv, "=")
      if (!(kv[1] in was)) continue        # client appeared after the last poll
      d = kv[2] - was[kv[1]]
      if (d > best) best = d
    }
    if (best < 0) exit
    p = best / el * 100
    printf "%.0f", (p < 0 ? 0 : (p > 100 ? 100 : p))
  }')

  read -r SYS_MEM_PCT SYS_MEM_USED SYS_MEM_TOTAL \
          SYS_SWAP_PCT SYS_SWAP_USED SYS_SWAP_TOTAL < <(sysstats::_memory)

  SYS_PKG_TEMP=$(sysstats::_package_temp)
  sysstats::_nvidia
}
