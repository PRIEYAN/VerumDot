#!/usr/bin/env bash
#
# Power center. Session controls in a rofi menu. Pure shell.

THEME=/home/prieyan/.config/hypr/apps/rofi/waybar-menu.rasi
HYPR_CONFIG=/home/prieyan/.config/hypr/apps/hyprlock/hyprlock.conf
SHUTDOWN_SCRIPT=/home/prieyan/.config/hypr/scripts/mogger_shutdown.sh

choice=$(printf '%s\n' \
  "  Lock" \
  "󰤄  Suspend" \
  "󰗽  Logout" \
  "  Reboot" \
  "⏻  Shutdown" \
  | rofi -dmenu -p "Power" -theme "$THEME")

case "$choice" in
  *Lock*)     setsid -f hyprlock -c "$HYPR_CONFIG" >/dev/null 2>&1 ;;
  *Suspend*)  systemctl suspend ;;
  *Logout*)   hyprctl dispatch exit ;;
  *Reboot*)   systemctl reboot ;;
  *Shutdown*) setsid -f "$SHUTDOWN_SCRIPT" >/dev/null 2>&1 ;;
  *)          exit 0 ;;
esac
