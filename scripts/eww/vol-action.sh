#!/usr/bin/env bash
#
# Volume action backend for the eww panel. Pure shell.
#   vol-action.sh set <0-150>
#   vol-action.sh mute


# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/_paths.sh"
EWW="eww -c "${HYPR_EWW}""
DIR="${HYPR_SCRIPTS}/eww"

case "$1" in
  set)
    vol=$2
    [ "$vol" -gt 150 ] 2>/dev/null && vol=150
    [ "$vol" -lt 0 ] 2>/dev/null && vol=0
    if command -v pamixer >/dev/null 2>&1; then
      pamixer --allow-boost --set-limit 150 --set-volume "$vol" >/dev/null 2>&1
    else
      wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ "$vol%" >/dev/null 2>&1
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
