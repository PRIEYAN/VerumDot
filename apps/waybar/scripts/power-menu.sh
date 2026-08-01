#!/usr/bin/env bash

# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../scripts" && pwd)/_paths.sh"
if [ "$1" = "menu" ]; then
  # Colored Icons only using Pango markup
  choice=$(printf "<span color='#FF3B30'></span>\n<span color='#AF52DE'></span>\n<span color='#007AFF'></span>\n<span color='#FF9500'></span>\n<span color='#34C759'>󰜺</span>" | rofi -dmenu -p "Power" -markup-rows -theme ~/.config/hypr/apps/rofi/power.rasi)
  case "$choice" in
    **) "${HYPR_SCRIPTS}/mogger_shutdown.sh";;
    **) systemctl reboot;;
    **) hyprctl dispatch exit;;
    **) hyprlock -c "${HYPR_APPS}/hyprlock/hyprlock.conf";;
    *󰜺*) systemctl suspend;;
    *) exit 0;;
  esac
  exit 0
fi
printf '{"text":"","tooltip":"Power menu: click to open"}'
