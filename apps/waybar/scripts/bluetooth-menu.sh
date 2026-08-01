#!/usr/bin/env bash

# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../scripts" && pwd)/_paths.sh"
if [ "$1" = "menu" ]; then
  if ! command -v bluetoothctl >/dev/null 2>&1; then
    rofi -e 'bluetoothctl not installed'
    exit 0
  fi
  status=$(bluetoothctl show | grep Powered | awk '{print $2}')
  choice=$(printf '%s
' "Refresh" "Show paired devices" "Toggle power" "Cancel" | rofi -dmenu -p "Bluetooth (Powered: $status)" -theme-str 'window { width: 24em; }')
  case "$choice" in
    Refresh)
      bluetoothctl scan on
      sleep 2
      bluetoothctl scan off ;;
    "Show paired devices")
      bluetoothctl paired-devices | awk '{print $3 " - " $4}' | rofi -dmenu -p 'Paired devices' -theme-str 'window { width: 24em; }' ;;
    "Toggle power")
      if [ "$status" = "yes" ]; then bluetoothctl power off; else bluetoothctl power on; fi ;;
    *) exit 0;;
  esac
  exit 0
fi
if command -v bluetoothctl >/dev/null 2>&1; then
  status=$(bluetoothctl show | grep Powered | awk '{print $2}')
  icon=''
  [ "$status" = "yes" ] && icon=''
  printf '{"text":"%s","tooltip":"Bluetooth %s"}' "$icon" "$status"
else
  printf '{"text":" n/a","tooltip":"bluetoothctl missing"}'
fi
