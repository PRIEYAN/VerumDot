#!/usr/bin/env bash
# Battery module for eww. Emits JSON {text, tooltip, class}.
#
# text:    a charge-level glyph + percentage
# tooltip: charging/discharging state + estimated time remaining
# class:   high|medium|low|charging (drives color, though the bar forces white)
#
# Reads the first battery under /sys/class/power_supply. Time remaining is
# computed from energy/charge and power/current when the kernel exposes them.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/json.sh"

# Read a sysfs attribute, trimmed; prints nothing (and fails) if absent.
read_attr() {
  [ -f "$1" ] || return 1
  local v
  v=$(cat "$1" 2>/dev/null) || return 1
  printf '%s' "$v"
}

# Locate a battery: prefer BAT*, else any supply whose type is "Battery".
find_battery() {
  local p
  for p in /sys/class/power_supply/BAT*; do
    [ -d "$p" ] && { printf '%s' "$p"; return 0; }
  done
  for p in /sys/class/power_supply/*; do
    [ -d "$p" ] || continue
    if [ "$(read_attr "$p/type" 2>/dev/null)" = "Battery" ]; then
      printf '%s' "$p"; return 0
    fi
  done
  return 1
}

GLYPHS_DISCHARGE=("" "" "" "" "" "" "" "" "" "" "")
CHARGING_GLYPH=""

# fmt_time <hours*100 as integer> -> "1h 05m" / "42m"; empty if <= 0 or invalid.
# Uses integer math scaled by 100 (no floating point in POSIX shell).
fmt_time() {
  local hx=$1
  [ -n "$hx" ] && [ "$hx" -gt 0 ] 2>/dev/null || return 0
  local total_min=$(( hx * 60 / 100 ))
  local h=$(( total_min / 60 ))
  local m=$(( total_min % 60 ))
  if [ "$h" -gt 0 ]; then
    printf '%dh %02dm' "$h" "$m"
  else
    printf '%dm' "$m"
  fi
}

emit() {
  # emit <text> <tooltip> <class>
  printf '{"text":%s,"tooltip":%s,"class":%s}\n' \
    "$(json_str "$1")" "$(json_str "$2")" "$(json_str "$3")"
}

main() {
  local bat
  bat=$(find_battery) || { emit "" "No battery" "high"; return; }

  local cap status pct
  cap=$(read_attr "$bat/capacity")
  status=$(read_attr "$bat/status"); [ -n "$status" ] || status="Unknown"
  case $cap in
    ''|*[!0-9]*) pct=0 ;;
    *) pct=$cap ;;
  esac

  # energy_* (Wh, µWh) preferred; fall back to charge_* (Ah, µAh)
  local now full rate
  now=$(read_attr "$bat/energy_now" || read_attr "$bat/charge_now")
  full=$(read_attr "$bat/energy_full" || read_attr "$bat/charge_full")
  rate=$(read_attr "$bat/power_now" || read_attr "$bat/current_now")

  # remaining time in hours*100 (integer), computed only when values are valid.
  local remaining=""
  case "$now$full$rate" in
    ''|*[!0-9]*) : ;;   # non-numeric or empty → skip
    *)
      if [ "$rate" -gt 0 ] 2>/dev/null; then
        if [ "$status" = "Charging" ]; then
          remaining=$(( (full - now) * 100 / rate ))
        elif [ "$status" = "Discharging" ]; then
          remaining=$(( now * 100 / rate ))
        fi
      fi
      ;;
  esac

  local icon cls tip t
  if [ "$status" = "Charging" ]; then
    icon=$CHARGING_GLYPH
    cls="charging"
    t=$(fmt_time "$remaining")
    if [ -n "$t" ]; then tip="Charging — ${pct}%, ${t} until full"; else tip="Charging — ${pct}%"; fi
  else
    local last=$(( ${#GLYPHS_DISCHARGE[@]} - 1 ))
    local idx=$(( pct * last / 100 ))
    [ "$idx" -gt "$last" ] && idx=$last
    icon=${GLYPHS_DISCHARGE[$idx]}
    if [ "$pct" -ge 60 ]; then cls="high"; elif [ "$pct" -ge 25 ]; then cls="medium"; else cls="low"; fi
    t=$(fmt_time "$remaining")
    if [ "$status" = "Full" ] || [ "$pct" -ge 99 ]; then
      tip="Full — ${pct}%"
    elif [ -n "$t" ]; then
      tip="${pct}%, ${t} remaining"
    else
      tip="${pct}%"
    fi
  fi

  emit "$icon ${pct}%" "$tip" "$cls"
}

main
