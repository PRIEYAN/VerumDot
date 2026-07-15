#!/usr/bin/env bash
#
# Calendar nav helper for the eww calendar panel. Pure shell.
# Bumps the month offset and re-renders. Called by the panel's
# prev/next buttons and by the Left/Right arrow keybinds.
#
#   eww-cal.sh prev | next | reset

EWW="eww -c /home/prieyan/.config/hypr/apps/eww"
SD=/home/prieyan/.config/hypr/scripts/eww
OFFSET_FILE=/tmp/eww-cal.offset

offset=0
[ -f "$OFFSET_FILE" ] && offset=$(cat "$OFFSET_FILE" 2>/dev/null)
case "$offset" in ''|*[!0-9-]*) offset=0 ;; esac

case "$1" in
  prev)  offset=$(( offset - 1 )) ;;
  next)  offset=$(( offset + 1 )) ;;
  reset) offset=0 ;;
esac

printf '%s' "$offset" > "$OFFSET_FILE"
$EWW update cal_offset="$offset" >/dev/null 2>&1
$EWW update cal_data="$($SD/cal-data.sh "$offset")" >/dev/null 2>&1
