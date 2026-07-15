#!/usr/bin/env bash

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

current_ssid() {
  nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}'
}

if [ "$1" = "menu" ]; then
  setsid -f /home/prieyan/.config/hypr/scripts/network-center.sh wifi >/tmp/network-center.log 2>&1
  exit 0
fi

active=$(current_ssid)
[ -z "$active" ] && active="None"
active_json=$(json_escape "$active")
printf '{"text":"󰤨 %s","tooltip":"Wi-Fi: %s"}\n' "$active_json" "$active_json"
