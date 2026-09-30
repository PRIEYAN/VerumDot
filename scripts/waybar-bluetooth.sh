#!/usr/bin/env bash
#
# Waybar bluetooth module. Click opens a rofi dropdown of paired devices.
#
# The click menu is *streamed* into rofi rather than collected first. rofi
# paints as soon as the first rows land on its stdin, so the dropdown is on
# screen immediately even when bluetoothd is still waking up; the device list
# is appended once bluetoothctl answers.


# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# "unknown" when bluetoothd does not answer in time. Callers treat that as
# "probably on" rather than showing a wrong "Bluetooth off" prompt.
bluetooth_powered() {
  out=$(timeout 2 bluetoothctl show 2>/dev/null)
  [ $? -eq 124 ] && { printf 'unknown'; return; }
  printf '%s' "$out" | awk '/Powered:/ {print $2; exit}'
}

connected_devices() {
  timeout 2 bluetoothctl devices Connected 2>/dev/null | sed 's/^Device [^ ]* //'
}

THEME="${HYPR_ROFI}/dropdown-right.rasi"

# Non-device rows. The case statement at the bottom ignores them, so a stray
# Enter on one does nothing.
HEADER="─────  Actions  ─────"
LOADING="󰑓  Loading devices…"
DEVICES="─────  Devices  ─────"
EMPTY="─────  No paired devices  ─────"

rmenu()   { rofi -dmenu -i -theme "$THEME" -p "$1"; }
rnotify() { command -v notify-send >/dev/null 2>&1 && notify-send -a "Bluetooth" "$1" "$2"; }

# Row: "<icon> <name>  ·  <state>". The name round-trips back to a MAC via
# name_to_mac (rofi can't carry a hidden field, so we look the MAC up again).
list_devices() {
  connected=$(timeout 5 bluetoothctl devices Connected 2>/dev/null | awk '{print $2}')
  timeout 5 bluetoothctl devices 2>/dev/null | while read -r _ mac name; do
    [ -z "$mac" ] && continue
    if printf '%s\n' "$connected" | grep -Fxq "$mac"; then
      printf '󰂱  %s  ·  connected  ✓\n' "$name"
    else
      printf '󰂲  %s  ·  paired\n' "$name"
    fi
  done
}

# Give bluetoothctl a short head start on a background fetch. If it answers in
# time the devices lead the menu as usual; if it is still stalling, rofi opens
# right away on a placeholder and the devices are appended underneath once they
# arrive. Either way the dropdown is on screen within a fraction of a second.
stream_menu() {
  header=$1; actions=$2
  tmp=$(mktemp -d 2>/dev/null) || { printf '%s\n%s\n' "$header" "$actions"; return; }
  out="${tmp}/devices"; flag="${tmp}/done"

  # Completion is signalled with a marker file rather than `kill -0 $!`: a
  # child that has finished but not been reaped still answers kill -0, which
  # would make every menu take the slow path.
  { list_devices >"$out" 2>/dev/null; : >"$flag"; } &

  waited=0
  while [ ! -e "$flag" ] && [ "$waited" -lt 4 ]; do
    sleep 0.1
    waited=$((waited + 1))
  done

  if [ -e "$flag" ]; then
    devs=$(cat "$out" 2>/dev/null)
    [ -n "$devs" ] && printf '%s\n' "$devs"
    printf '%s\n%s\n' "$header" "$actions"
  else
    # Still stalling: draw the menu now, fill the devices in underneath after.
    printf '%s\n' "$LOADING"
    printf '%s\n%s\n' "$header" "$actions"
    while [ ! -e "$flag" ] && [ "$waited" -lt 150 ]; do
      sleep 0.1
      waited=$((waited + 1))
    done
    devs=$(cat "$out" 2>/dev/null)
    if [ -n "$devs" ]; then
      printf '%s\n%s\n' "$DEVICES" "$devs"
    else
      # Nothing came back, so retire the placeholder with a real answer.
      printf '%s\n' "$EMPTY"
    fi
  fi

  rm -rf "$tmp"
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
  if [ "$powered" != "yes" ] && [ "$powered" != "unknown" ]; then
    choice=$(printf '%s\n' "󰂯  Turn Bluetooth on" "  Close" | rmenu "Bluetooth off")
    case "$choice" in
      *"Turn Bluetooth on"*) bluetoothctl power on >/dev/null 2>&1 ;;
    esac
    exit 0
  fi

  header="$HEADER"
  actions=$(printf '%s\n' \
    "󰂰  Scan & pair new device" \
    "󰂲  Turn Bluetooth off" \
    "󰒓  Bluetooth manager")

  choice=$(stream_menu "$header" "$actions" | rmenu "Bluetooth")
  [ -z "$choice" ] && exit 0

  case "$choice" in
    *"Scan & pair new device"*) scan_and_pair ;;
    *"Turn Bluetooth off"*)     bluetoothctl power off >/dev/null 2>&1 ;;
    *"Bluetooth manager"*)      setsid -f blueman-manager >/dev/null 2>&1 ;;
    "$header")                  : ;;
    "$LOADING"|"$DEVICES"|"$EMPTY") : ;;  # placeholder / divider, ignore
    *)
      name=$(row_name "$choice"); mac=$(name_to_mac "$name")
      [ -n "$mac" ] && toggle_device "$mac" "$name" ;;
  esac
  exit 0
fi

# Bar output is the glyph alone — what is actually connected lives in the
# hover tooltip, and the device list lives in the quickshell control centre.
if command -v bluetoothctl >/dev/null 2>&1; then
  status=$(bluetooth_powered)
  connected=$(connected_devices | head -n 1)
  if [ -n "$connected" ]; then
    connected_json=$(json_escape "$connected")
    printf '{"text":"󰂱","tooltip":"Bluetooth \u00b7 %s","class":"connected"}\n' "$connected_json"
  elif [ "$status" = "yes" ]; then
    printf '{"text":"󰂯","tooltip":"Bluetooth \u00b7 on, nothing connected","class":"on"}\n'
  elif [ "$status" = "unknown" ]; then
    printf '{"text":"󰂯","tooltip":"Bluetooth \u00b7 starting up","class":"on"}\n'
  else
    printf '{"text":"󰂲","tooltip":"Bluetooth \u00b7 off","class":"off"}\n'
  fi
else
  printf '{"text":"󰂲","tooltip":"bluetoothctl missing","class":"off"}\n'
fi
