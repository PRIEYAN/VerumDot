#!/usr/bin/env bash
#
# Toggle the eww calendar panel. Resets to the current month on open.

EWW="eww -c /home/prieyan/.config/hypr/apps/eww"

if $EWW active-windows 2>/dev/null | grep -q '^calendar'; then
  $EWW close calendar
  hyprctl dispatch submap reset >/dev/null 2>&1
else
  /home/prieyan/.config/hypr/scripts/eww-cal.sh reset
  $EWW open calendar
  # Enter the calendar submap so Left/Right change months, Esc closes.
  hyprctl dispatch submap calendar >/dev/null 2>&1
fi
