#!/usr/bin/env bash
#
# Network action backend for the eww panel. Pure shell.
# Performs an action then refreshes the eww vars and waybar.
#
#   net-action.sh wifi-toggle
#   net-action.sh wifi-connect <ssid> [password]
#   net-action.sh wifi-disconnect
#   net-action.sh bt-toggle
#   net-action.sh bt-connect <mac>
#   net-action.sh bt-disconnect <mac>

DIR=/home/prieyan/.config/hypr/scripts/eww
EWW="eww -c /home/prieyan/.config/hypr/apps/eww"

refresh() {
  # Re-poll the eww variables that back the panel, and nudge waybar.
  $EWW update net_state="$($DIR/net-data.sh state)" >/dev/null 2>&1
  $EWW update net_known="$($DIR/net-data.sh known)" >/dev/null 2>&1
  $EWW update net_other="$($DIR/net-data.sh other)" >/dev/null 2>&1
  $EWW update bt_state="$($DIR/net-data.sh bt-state)" >/dev/null 2>&1
  $EWW update bt_devices="$($DIR/net-data.sh bt-devices)" >/dev/null 2>&1
  pkill -RTMIN+8 waybar >/dev/null 2>&1
  pkill -RTMIN+9 waybar >/dev/null 2>&1
}

wifi_device() {
  nmcli -t -f device,type device status 2>/dev/null | awk -F: '$2=="wifi"{print $1; exit}'
}

case "$1" in
  wifi-toggle)
    if [ "$(nmcli radio wifi 2>/dev/null)" = "enabled" ]; then
      nmcli radio wifi off
    else
      nmcli radio wifi on
    fi
    ;;
  wifi-connect)
    ssid=$2
    pw=$3
    [ -z "$ssid" ] && exit 0
    if nmcli connection show "$ssid" >/dev/null 2>&1; then
      nmcli connection up "$ssid" >/dev/null 2>&1
    elif [ -n "$pw" ]; then
      nmcli device wifi connect "$ssid" password "$pw" >/dev/null 2>&1
    else
      nmcli device wifi connect "$ssid" >/dev/null 2>&1
    fi
    # Clear the typed password field regardless of outcome.
    $EWW update wifi_pw="" wifi_pw_target="" >/dev/null 2>&1
    ;;
  wifi-disconnect)
    dev=$(wifi_device)
    [ -n "$dev" ] && nmcli device disconnect "$dev" >/dev/null 2>&1
    ;;
  bt-toggle)
    powered=$(bluetoothctl show 2>/dev/null | awk '/Powered:/ {print $2; exit}')
    if [ "$powered" = "yes" ]; then
      bluetoothctl power off >/dev/null 2>&1
    else
      bluetoothctl power on >/dev/null 2>&1
      bluetoothctl --timeout 4 scan on >/dev/null 2>&1
    fi
    ;;
  bt-connect)
    [ -n "$2" ] && bluetoothctl connect "$2" >/dev/null 2>&1
    ;;
  bt-disconnect)
    [ -n "$2" ] && bluetoothctl disconnect "$2" >/dev/null 2>&1
    ;;
esac

refresh
