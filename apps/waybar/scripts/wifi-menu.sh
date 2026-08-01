#!/usr/bin/env bash

# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../scripts" && pwd)/_paths.sh"
if [ "$1" = "menu" ]; then
  ssid=$(nmcli -t -f active,ssid dev wifi | awk -F: '$1=="yes"{print $2; exit}')
  [ -z "$ssid" ] && ssid="Not connected"
  choice=$(printf '%s
' "Refresh" "Connect new network" "Hotspot" "Cancel" | rofi -dmenu -p "Wi-Fi (${ssid})" -theme-str 'window { width: 24em; }')
  case "$choice" in
    Refresh)
      nmcli device wifi rescan ;;
    "Connect new network")
      ssid=$(nmcli -t -f ssid dev wifi | grep -v '^$' | sort -u | rofi -dmenu -p 'SSID' -theme-str 'window { width: 24em; }')
      if [ -n "$ssid" ]; then
        password=$(rofi -dmenu -password -p "Password for $ssid" -theme-str 'window { width: 24em; }')
        nmcli device wifi connect "$ssid" password "$password"
      fi ;;
    Hotspot)
      hotspot_name=$(rofi -dmenu -p 'Hotspot SSID' -theme-str 'window { width: 24em; }' <<<"MyHotspot")
      hotspot_pass=$(rofi -dmenu -password -p 'Hotspot Password' -theme-str 'window { width: 24em; }' <<<"securepass")
      if [ -n "$hotspot_name" ] && [ -n "$hotspot_pass" ]; then
        nmcli device wifi hotspot ssid "$hotspot_name" password "$hotspot_pass"
      fi ;;
    *) exit 0;;
  esac
  exit 0
fi
active=$(nmcli -t -f active,ssid dev wifi | awk -F: '$1=="yes"{print $2; exit}')
[ -z "$active" ] && active="None"
printf '{"text":" %s","tooltip":"Connected: %s"}' "$active" "$active"
