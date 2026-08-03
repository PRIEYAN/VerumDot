#!/usr/bin/env bash
#
# Low-battery mako alerts at 20% and 15%.
# Fires once per threshold while discharging; resets after charge climbs
# back above that threshold (or while AC is plugged in).

# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"

STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hypr-battery"
mkdir -p "$STATE_DIR"

bat_path() {
  local d
  for d in /sys/class/power_supply/BAT*; do
    [[ -r "$d/capacity" ]] && { printf '%s\n' "$d"; return 0; }
  done
  return 1
}

notify_once() {
  local level=$1 title=$2 body=$3 urgency=$4
  local flag="$STATE_DIR/notified-${level}"
  [[ -f "$flag" ]] && return 0
  notify-send -u "$urgency" -a "VerumDot" -i battery-caution \
    "$title" "$body" 2>/dev/null \
    || notify-send -u "$urgency" -a "VerumDot" "$title" "$body"
  : >"$flag"
}

clear_flag() {
  rm -f "$STATE_DIR/notified-$1"
}

BAT="$(bat_path)" || exit 0

while :; do
  cap=$(cat "$BAT/capacity" 2>/dev/null || echo 100)
  status=$(cat "$BAT/status" 2>/dev/null || echo Unknown)

  # Charging / full → clear flags so the next discharge can alert again.
  if [[ "$status" == "Charging" || "$status" == "Full" || "$status" == "Not charging" ]]; then
    clear_flag 20
    clear_flag 15
  else
    # Discharging (or Unknown): fire thresholds once each.
    if (( cap <= 15 )); then
      notify_once 15 "Battery critical — ${cap}%" \
        "Plug in soon. Battery is at ${cap}%." critical
      # Hitting 15 also covers 20 — mark both so we don't double-spam.
      : >"$STATE_DIR/notified-20"
    elif (( cap <= 20 )); then
      notify_once 20 "Battery low — ${cap}%" \
        "Battery is at ${cap}%. Consider plugging in." critical
    else
      # Climbed back above a threshold without AC (rare) → allow re-alert.
      (( cap > 20 )) && clear_flag 20
      (( cap > 15 )) && clear_flag 15
    fi
  fi

  sleep 30
done
