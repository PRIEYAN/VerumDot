#!/usr/bin/env bash
# Adjust output volume by 5% via pamixer, then push the fresh value into eww
# immediately so the bar updates instantly instead of waiting for the poll.
# Usage: volume-adjust.sh up|down

case "$1" in
  up)   pamixer -i 5 ;;
  down) pamixer -d 5 ;;
esac

json=$(/home/prieyan/.config/hypr/scripts/status-volume.sh)
text=$(printf '%s' "$json" | jq -r '.text // ""')
tooltip=$(printf '%s' "$json" | jq -r '.tooltip // ""')
class=$(printf '%s' "$json" | jq -r '.class // ""')
eww update "volume_text=$text" "volume_tooltip=$tooltip" "volume_class=$class" >/dev/null 2>&1
