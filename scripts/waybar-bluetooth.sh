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

THEME=/home/prieyan/.config/hypr/apps/rofi/dropdown-right.rasi
rmenu()   { rofi -dmenu -i -theme "$THEME" -p "$1"; }
rnotify() { command -v notify-send >/dev/null 2>&1 && notify-send -a "Bluetooth" "$1" "$2"; }

# Row: "<icon> <name>  ·  <state>". The name round-trips back to a MAC via
# name_to_mac (rofi can't carry a hidden field, so we look the MAC up again).
list_devices() {
  connected=$(bluetoothctl devices Connected 2>/dev/null | awk '{print $2}')
  bluetoothctl devices 2>/dev/null | while read -r _ mac name; do
    [ -z "$mac" ] && continue
    if printf '%s\n' "$connected" | grep -Fxq "$mac"; then
      printf '󰂱  %s  ·  connected  ✓\n' "$name"
    else
      printf '󰂲  %s  ·  paired\n' "$name"
    fi
  done
}

# Strip icon prefix and trailing state to recover the device name.
row_name() { printf '%s' "$1" | sed -E 's/^[^ ]+  //; s/  ·.*$//'; }

# Look up a device's MAC by its (unique) name.
name_to_mac() {
  bluetoothctl devices 2>/dev/null \
    | sed -E 's/^Device ([0-9A-F:]+) (.*)$/\1\t\2/I' \
    | awk -F'\t' -v n="$1" '$2 == n {print $1; exit}'
}

# Toggle connect/disconnect for a device by MAC.
toggle_device() {
  mac=$1; name=$2
  if bluetoothctl devices Connected 2>/dev/null | awk '{print $2}' | grep -Fxq "$mac"; then
    bluetoothctl disconnect "$mac" >/dev/null 2>&1
    rnotify "Disconnected" "$name"
  else
    if bluetoothctl connect "$mac" >/dev/null 2>&1; then
      rnotify "Connected" "$name"
    else
      rnotify "Connect failed" "$name"
    fi
  fi
}

# Scan for nearby devices, then let the user pick one to pair+connect.
scan_and_pair() {
  rnotify "Scanning…" "Looking for nearby Bluetooth devices"
  bluetoothctl --timeout 8 scan on >/dev/null 2>&1
  rows=$(bluetoothctl devices 2>/dev/null | while read -r _ mac name; do
           [ -z "$mac" ] && continue
           printf '󰂲  %s\n' "$name"
         done)
  [ -z "$rows" ] && { rnotify "No devices found" "Try again"; return; }
  choice=$(printf '%s' "$rows" | rmenu "Pair device")
  [ -z "$choice" ] && return
  name=$(row_name "$choice"); mac=$(name_to_mac "$name")
  [ -z "$mac" ] && return
  bluetoothctl pair "$mac" >/dev/null 2>&1
  bluetoothctl trust "$mac" >/dev/null 2>&1
  if bluetoothctl connect "$mac" >/dev/null 2>&1; then
    rnotify "Connected" "$name"
  else
    rnotify "Paired" "$name (not connected)"
  fi
}

if [ "$1" = "menu" ]; then
  if ! command -v bluetoothctl >/dev/null 2>&1; then
    rnotify "bluetoothctl missing" "Install bluez-utils"; exit 0
  fi

  powered=$(bluetooth_powered)
  if [ "$powered" != "yes" ]; then
    choice=$(printf '%s\n' "󰂯  Turn Bluetooth on" "  Close" | rmenu "Bluetooth off")
    case "$choice" in
      *"Turn Bluetooth on"*) bluetoothctl power on >/dev/null 2>&1 ;;
    esac
    exit 0
  fi

  header="─────  Actions  ─────"
  actions=$(printf '%s\n' \
    "󰂰  Scan & pair new device" \
    "󰂲  Turn Bluetooth off" \
    "󰒓  Bluetooth manager")

  devs=$(list_devices)
  choice=$(printf '%s\n%s\n%s' "$devs" "$header" "$actions" | rmenu "Bluetooth")
  [ -z "$choice" ] && exit 0

  case "$choice" in
    *"Scan & pair new device"*) scan_and_pair ;;
    *"Turn Bluetooth off"*)     bluetoothctl power off >/dev/null 2>&1 ;;
    *"Bluetooth manager"*)      setsid -f blueman-manager >/dev/null 2>&1 ;;
    "$header")                  : ;;
    *)
      name=$(row_name "$choice"); mac=$(name_to_mac "$name")
      [ -n "$mac" ] && toggle_device "$mac" "$name" ;;
  esac
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
