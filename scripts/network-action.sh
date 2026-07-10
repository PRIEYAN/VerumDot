#!/usr/bin/env bash
# Runs a network/bluetooth mutation, then nudges network-watch.sh to
# re-emit fresh state on its current page. Used by eww's Network Center.
#
# Usage: network-action.sh <page> <action> [args...]
#   page:   wifi | bluetooth
#   action: connect <ssid> [password] | connect-hidden <ssid> <password> |
#           hotspot <ssid> <password> | disconnect | toggle-power |
#           bt-connect <mac> | bt-disconnect <mac> | bt-forget <mac> |
#           bt-pair <mac> | rescan

fifo="${XDG_RUNTIME_DIR:-/tmp}/eww-network-center/cmd.fifo"
page="$1"; action="$2"; shift 2

case "$page:$action" in
  wifi:connect)
    ssid="$1"; password="$2"
    if nmcli connection show "$ssid" >/dev/null 2>&1; then
      nmcli connection up "$ssid" >/dev/null 2>&1
    elif [ -n "$password" ]; then
      nmcli device wifi connect "$ssid" password "$password" >/dev/null 2>&1
    else
      nmcli device wifi connect "$ssid" >/dev/null 2>&1
    fi
    ;;
  wifi:connect-hidden)
    ssid="$1"; password="$2"
    nmcli device wifi connect "$ssid" password "$password" hidden yes >/dev/null 2>&1
    ;;
  wifi:hotspot)
    ssid="$1"; password="$2"
    nmcli device wifi hotspot ssid "$ssid" password "$password" >/dev/null 2>&1
    ;;
  wifi:disconnect)
    device=$(nmcli -t -f device,type device status | awk -F: '$2=="wifi"{print $1; exit}')
    [ -n "$device" ] && nmcli device disconnect "$device" >/dev/null 2>&1
    ;;
  wifi:toggle-power)
    state=$(nmcli radio wifi)
    nmcli radio wifi "$([ "$state" = "enabled" ] && echo off || echo on)" >/dev/null 2>&1
    ;;
  wifi:rescan)
    nmcli device wifi rescan >/dev/null 2>&1
    ;;
  bluetooth:bt-connect)
    bluetoothctl connect "$1" >/dev/null 2>&1
    ;;
  bluetooth:bt-disconnect)
    bluetoothctl disconnect "$1" >/dev/null 2>&1
    ;;
  bluetooth:bt-forget)
    bluetoothctl remove "$1" >/dev/null 2>&1
    ;;
  bluetooth:bt-pair)
    mac="$1"
    bluetoothctl pair "$mac" >/dev/null 2>&1
    bluetoothctl trust "$mac" >/dev/null 2>&1
    bluetoothctl connect "$mac" >/dev/null 2>&1
    ;;
  bluetooth:toggle-power)
    powered=$(bluetoothctl show | awk '/Powered:/ {print $2; exit}')
    bluetoothctl power "$([ "$powered" = "yes" ] && echo off || echo on)" >/dev/null 2>&1
    ;;
  bluetooth:rescan)
    bluetoothctl power on >/dev/null 2>&1
    timeout 4 bluetoothctl scan on >/dev/null 2>&1
    ;;
esac

[ -p "$fifo" ] && printf 'page:%s\n' "$page" > "$fifo"
