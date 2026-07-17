#!/usr/bin/env bash
#
# Waybar wifi/ethernet module. Shows an ethernet glyph when a wired
# connection is up, otherwise the connected SSID. Click opens
# nm-connection-editor. Pure shell.

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

ethernet_iface() {
  nmcli -t -f device,type,state device status 2>/dev/null \
    | awk -F: '$2=="ethernet" && $3=="connected"{print $1; exit}'
}

current_ssid() {
  nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}'
}

if [ "$1" = "menu" ]; then
  setsid -f nm-connection-editor >/dev/null 2>&1
  exit 0
fi

eth=$(ethernet_iface)
if [ -n "$eth" ]; then
  # Wired connection: ethernet glyph + label.
  printf '{"text":"󰈀 Ethernet","tooltip":"Ethernet connected (%s)","class":"ethernet"}\n' "$(json_escape "$eth")"
  exit 0
fi

active=$(current_ssid)
if [ -n "$active" ]; then
  active_json=$(json_escape "$active")
  printf '{"text":"󰤨 %s","tooltip":"Wi-Fi: %s","class":"wifi"}\n' "$active_json" "$active_json"
else
  printf '{"text":"󰤮","tooltip":"Wi-Fi: not connected","class":"disconnected"}\n'
fi
