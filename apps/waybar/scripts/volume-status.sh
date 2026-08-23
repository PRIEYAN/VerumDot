#!/usr/bin/env bash
# Volume level for waybar.

if volume=$(pamixer --get-volume 2>/dev/null); then
  mute=$(pamixer --get-mute 2>/dev/null)
  case "$mute" in
    true|1) icon=$'' ;;
    *)      icon=$'' ;;
  esac
  text="${icon} ${volume}%"
  tooltip='Click to toggle mute | Scroll to change volume'
else
  text=$' n/a'
  tooltip='pamixer not available'
fi

jq -nc --arg t "$text" --arg tt "$tooltip" '{text:$t, tooltip:$tt}'
