#!/usr/bin/env bash

if [ "$1" = "menu" ]; then
  # Toggle: if the rofi menu is already open, close it.
  if pgrep -f "power-center.sh" >/dev/null; then
    pkill -f "power-center.sh"
    exit 0
  fi
  # Run the rofi menu inline (blocking) so it attaches to the Wayland
  # session, exactly like waybar-volume.sh. Do NOT `setsid -f` it: a
  # detached, terminal-less session makes rofi fail to map and nothing
  # appears.
  /home/prieyan/.config/hypr/scripts/power-center.sh
  exit 0
fi

printf '{"text":"⏻","tooltip":"Power"}\n'
