#!/usr/bin/env bash

theme="/home/prieyan/.config/hypr/apps/rofi/waybar-menu.rasi"

current_ssid() {
  nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}'
}

if [ "$1" = "menu" ]; then
  ssid=$(current_ssid)
  [ -z "$ssid" ] && ssid="Not connected"

  choice=$(printf '%s\n' \
    "󰤨  Connected: $ssid" \
    "󰑐  Refresh networks" \
    "󰤓  Connect new network" \
    "󱜠  Hotspot" \
    "󰜺  Cancel" |
    rofi -dmenu -p "Wi-Fi" -theme "$theme")

  case "$choice" in
    *"Refresh networks"*)
      nmcli device wifi rescan ;;
    *"Connect new network"*)
      network=$(nmcli -t -f ssid dev wifi 2>/dev/null | awk 'NF' | sort -u | rofi -dmenu -p "SSID" -theme "$theme")
      if [ -n "$network" ]; then
        password=$(rofi -dmenu -password -p "Password" -theme "$theme")
        if [ -n "$password" ]; then
          nmcli device wifi connect "$network" password "$password"
        else
          nmcli device wifi connect "$network"
        fi
      fi ;;
    *"Hotspot"*)
      hotspot_name=$(printf '%s\n' "MyHotspot" | rofi -dmenu -p "Hotspot SSID" -theme "$theme")
      hotspot_pass=$(printf '%s\n' "securepass" | rofi -dmenu -password -p "Hotspot Password" -theme "$theme")
      if [ -n "$hotspot_name" ] && [ -n "$hotspot_pass" ]; then
        nmcli device wifi hotspot ssid "$hotspot_name" password "$hotspot_pass"
      fi ;;
    *) exit 0 ;;
  esac
  exit 0
fi

active=$(current_ssid)
[ -z "$active" ] && active="None"
printf '{"text":"󰤨 %s","tooltip":"Wi-Fi: %s"}\n' "$active" "$active"
