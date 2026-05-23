#!/usr/bin/env bash

if [ "$1" = "menu" ]; then
  choice=$(printf '%s\n' "⏻  Shutdown" "  Lock" "  Logout" "↻  Reboot" "⏾  Suspend" | rofi -dmenu -p "Power" -theme /home/prieyan/.config/hypr/apps/rofi/waybar-menu.rasi)
  case "$choice" in
    *Shutdown*) /home/prieyan/.config/hypr/scripts/mogger_shutdown.sh ;;
    *Reboot*) systemctl reboot ;;
    *Logout*) hyprctl dispatch exit ;;
    *Lock*) hyprlock -c /home/prieyan/.config/hypr/apps/hyprlock/hyprlock.conf ;;
    *Suspend*) systemctl suspend ;;
    *) exit 0 ;;
  esac
  exit 0
fi

printf '{"text":"⏻","tooltip":"Power menu"}\n'
