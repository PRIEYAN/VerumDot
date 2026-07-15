#!/usr/bin/env bash
#
# Volume action backend for the eww panel. Pure shell.
#   vol-action.sh set <0-100>
#   vol-action.sh mute

EWW="eww -c /home/prieyan/.config/hypr/apps/eww"
DIR=/home/prieyan/.config/hypr/scripts/eww

case "$1" in
  set)
    if command -v pamixer >/dev/null 2>&1; then
      pamixer --set-volume "$2" >/dev/null 2>&1
    else
      wpctl set-volume @DEFAULT_AUDIO_SINK@ "$2%" >/dev/null 2>&1
    fi
    ;;
  mute)
    if command -v pamixer >/dev/null 2>&1; then
      pamixer -t >/dev/null 2>&1
    else
      wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle >/dev/null 2>&1
    fi
    ;;
esac

$EWW update vol_state="$($DIR/vol-data.sh)" >/dev/null 2>&1
pkill -RTMIN+1 waybar >/dev/null 2>&1
