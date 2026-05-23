#!/usr/bin/env bash

theme="/home/prieyan/.config/hypr/apps/rofi/waybar-menu.rasi"

bluetooth_powered() {
  bluetoothctl show 2>/dev/null | awk '/Powered:/ {print $2; exit}'
}

connected_devices() {
  bluetoothctl devices Connected 2>/dev/null | sed 's/^Device [^ ]* //'
}

if [ "$1" = "menu" ]; then
  if ! command -v bluetoothctl >/dev/null 2>&1; then
    rofi -e "bluetoothctl not installed" -theme "$theme"
    exit 0
  fi

  status=$(bluetooth_powered)
  [ -z "$status" ] && status="unknown"

  connected=$(connected_devices | paste -sd ", " -)
  [ -z "$connected" ] && connected="No devices connected"

  choice=$(printf '%s\n' \
    "  Powered: $status" \
    "󰂯  Connected: $connected" \
    "󰑐  Scan / refresh" \
    "󰂲  Paired devices" \
    "⏻  Toggle power" \
    "󰜺  Cancel" |
    rofi -dmenu -p "Bluetooth" -theme "$theme")

  case "$choice" in
    *"Scan / refresh"*)
      bluetoothctl scan on
      sleep 2
      bluetoothctl scan off ;;
    *"Paired devices"*)
      device=$(bluetoothctl paired-devices | sed 's/^Device //' | rofi -dmenu -p "Paired devices" -theme "$theme")
      [ -n "$device" ] || exit 0
      mac=${device%% *}
      action=$(printf '%s\n' "Connect" "Disconnect" "Trust" "Remove" "Cancel" | rofi -dmenu -p "$mac" -theme "$theme")
      case "$action" in
        Connect) bluetoothctl connect "$mac" ;;
        Disconnect) bluetoothctl disconnect "$mac" ;;
        Trust) bluetoothctl trust "$mac" ;;
        Remove) bluetoothctl remove "$mac" ;;
      esac ;;
    *"Toggle power"*)
      if [ "$status" = "yes" ]; then
        bluetoothctl power off
      else
        bluetoothctl power on
      fi ;;
    *) exit 0 ;;
  esac
  exit 0
fi

if command -v bluetoothctl >/dev/null 2>&1; then
  status=$(bluetooth_powered)
  [ -z "$status" ] && status="unknown"
  connected=$(connected_devices | head -n 1)
  if [ -n "$connected" ]; then
    printf '{"text":" %s","tooltip":"Bluetooth connected: %s"}\n' "$connected" "$connected"
  else
    printf '{"text":"","tooltip":"Bluetooth: %s"}\n' "$status"
  fi
else
  printf '{"text":" n/a","tooltip":"bluetoothctl missing"}\n'
fi
