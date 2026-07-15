#!/usr/bin/env bash
#
# Power action backend for the eww panel. Pure shell.
# Closes the panel first, then runs the session action.

EWW="eww -c /home/prieyan/.config/hypr/apps/eww"
HYPR_CONFIG=/home/prieyan/.config/hypr/apps/hyprlock/hyprlock.conf
SHUTDOWN_SCRIPT=/home/prieyan/.config/hypr/scripts/mogger_shutdown.sh

$EWW close power >/dev/null 2>&1

case "$1" in
  lock)     setsid -f hyprlock -c "$HYPR_CONFIG" >/dev/null 2>&1 ;;
  suspend)  systemctl suspend ;;
  logout)   hyprctl dispatch exit ;;
  reboot)   systemctl reboot ;;
  shutdown) setsid -f "$SHUTDOWN_SCRIPT" >/dev/null 2>&1 ;;
esac
