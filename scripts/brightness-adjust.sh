#!/usr/bin/env bash
# Adjust screen brightness via brightnessctl, then push the fresh value into
# eww immediately so the bar updates instantly instead of waiting for the
# next poll tick. Usage: brightness-adjust.sh up|down

case "$1" in
  up)   brightnessctl set +5% -q ;;
  down) brightnessctl set 5%- -q ;;
esac

# Recompute display fields once and update the eww vars right now.
json=$(/home/prieyan/.config/hypr/scripts/brightness-status.sh)
text=$(printf '%s' "$json" | jq -r '.text // ""')
tooltip=$(printf '%s' "$json" | jq -r '.tooltip // ""')
eww update "brightness_text=$text" "brightness_tooltip=$tooltip" >/dev/null 2>&1
