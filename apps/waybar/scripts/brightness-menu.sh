#!/usr/bin/env bash

# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../scripts" && pwd)/_paths.sh"
if command -v brightnessctl >/dev/null 2>&1; then
  choice=$(printf '%s
' "10%" "20%" "50%" "75%" "100%" | rofi -dmenu -p "Brightness" -theme-str 'window { width: 20em; }')
  case "$choice" in
    "10%") brightnessctl set 10%;;
    "20%") brightnessctl set 20%;;
    "50%") brightnessctl set 50%;;
    "75%") brightnessctl set 75%;;
    "100%") brightnessctl set 100%;;
    *) exit 0;;
  esac
else
  rofi -e 'brightnessctl not installed'
fi
