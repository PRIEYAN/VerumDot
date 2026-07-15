#!/usr/bin/env bash

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

current_ssid() {
  nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}'
}

if [ "$1" = "menu" ]; then
  # Run inline (blocking) so rofi attaches to the Wayland session.
  /home/prieyan/.config/hypr/scripts/network-center.sh wifi
  exit 0
fi

active=$(current_ssid)
[ -z "$active" ] && active="None"
active_json=$(json_escape "$active")
printf '{"text":"󰤨 %s","tooltip":"Wi-Fi: %s"}\n' "$active_json" "$active_json"
