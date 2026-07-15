#!/usr/bin/env bash

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

bluetooth_powered() {
  bluetoothctl show 2>/dev/null | awk '/Powered:/ {print $2; exit}'
}

connected_devices() {
  bluetoothctl devices Connected 2>/dev/null | sed 's/^Device [^ ]* //'
}

if [ "$1" = "menu" ]; then
  # Run inline (blocking) so rofi attaches to the Wayland session.
  /home/prieyan/.config/hypr/scripts/network-center.sh bluetooth
  exit 0
fi

if command -v bluetoothctl >/dev/null 2>&1; then
  status=$(bluetooth_powered)
  [ -z "$status" ] && status="unknown"
  connected=$(connected_devices | head -n 1)
  if [ -n "$connected" ]; then
    connected_json=$(json_escape "$connected")
    printf '{"text":" %s","tooltip":"Bluetooth connected: %s"}\n' "$connected_json" "$connected_json"
  else
    status_json=$(json_escape "$status")
    printf '{"text":"","tooltip":"Bluetooth: %s"}\n' "$status_json"
  fi
else
  printf '{"text":" n/a","tooltip":"bluetoothctl missing"}\n'
fi
