#!/usr/bin/env bash
#
# Network center. Wi-Fi and Bluetooth management in rofi menus.
# Pure shell -- drives nmcli and bluetoothctl. Passwords are read with
# rofi's -password mode. Refreshes waybar after actions (RTMIN+8 wifi,
# RTMIN+9 bluetooth), matching the old python center.
#
# Usage: network-center.sh [wifi|bluetooth]

THEME=/home/prieyan/.config/hypr/apps/rofi/waybar-menu.rasi
PAGE=${1:-wifi}

menu() {
  rofi -dmenu -i -p "$1" -theme "$THEME"
}

ask() {
  printf '' | rofi -dmenu -p "$1" -theme "$THEME"
}

ask_password() {
  printf '' | rofi -dmenu -password -p "$1" -theme "$THEME"
}

refresh_waybar() {
  if [ "$PAGE" = "wifi" ]; then
    pkill -RTMIN+8 waybar >/dev/null 2>&1
  else
    pkill -RTMIN+9 waybar >/dev/null 2>&1
  fi
}

# ---------------------------------------------------------------- wifi

wifi_current() {
  nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}'
}

wifi_device() {
  nmcli -t -f device,type device status 2>/dev/null | awk -F: '$2=="wifi"{print $1; exit}'
}

wifi_connect() {
  ssid=$1
  security=$2
  if nmcli connection show "$ssid" >/dev/null 2>&1; then
    nmcli connection up "$ssid" >/dev/null 2>&1
  elif [ "$security" = "secured" ]; then
    pw=$(ask_password "password for $ssid")
    [ -z "$pw" ] && return
    nmcli device wifi connect "$ssid" password "$pw" >/dev/null 2>&1
  else
    nmcli device wifi connect "$ssid" >/dev/null 2>&1
  fi
  refresh_waybar
}

wifi_list() {
  # One row per unique ssid: "  ssid  (signal% / secured|open)"
  nmcli -t -f in-use,ssid,signal,security dev wifi list 2>/dev/null \
    | awk -F: '
        $2 != "" && !seen[$2]++ {
          sec = ($4 == "" || $4 == "--") ? "open" : "secured"
          mark = ($1 == "*") ? "" : ""
          printf "%s  %s  (%s%% / %s)\n", mark, $2, $3, sec
        }'
}

wifi_menu() {
  current=$(wifi_current)
  [ -z "$current" ] && current="not connected"
  radio=$(nmcli radio wifi 2>/dev/null)

  choice=$(printf '%s\n%s\n' \
    "  refresh" \
    "  disconnect" \
    "  power ($radio)" \
    "  hidden network" \
    | { cat; nmcli device wifi rescan >/dev/null 2>&1; wifi_list; } \
    | menu "Wi-Fi [$current]")

  case "$choice" in
    "")            exit 0 ;;
    *refresh*)     wifi_menu ;;
    *disconnect*)  dev=$(wifi_device); [ -n "$dev" ] && nmcli device disconnect "$dev" >/dev/null 2>&1; refresh_waybar; wifi_menu ;;
    *power*)
      if [ "$radio" = "enabled" ]; then nmcli radio wifi off; else nmcli radio wifi on; fi
      refresh_waybar; wifi_menu ;;
    *"hidden network"*)
      ssid=$(ask "hidden network name"); [ -z "$ssid" ] && wifi_menu
      pw=$(ask_password "password for $ssid")
      [ -n "$pw" ] && nmcli device wifi connect "$ssid" password "$pw" hidden yes >/dev/null 2>&1
      refresh_waybar; wifi_menu ;;
    *)
      # A network row: "  ssid  (85% / secured)". Strip icon + trailing meta.
      ssid=$(printf '%s' "$choice" | sed -E 's/^[^ ]*  //; s/  \([^)]*\)$//')
      security=open
      printf '%s' "$choice" | grep -q 'secured)' && security=secured
      wifi_connect "$ssid" "$security"
      wifi_menu ;;
  esac
}

# ------------------------------------------------------------- bluetooth

bt_powered() {
  bluetoothctl show 2>/dev/null | awk '/Powered:/ {print $2; exit}'
}

bt_state() {
  info=$(bluetoothctl info "$1" 2>/dev/null)
  case "$info" in
    *"Connected: yes"*) printf 'connected'; return ;;
  esac
  paired=no; trusted=no
  case "$info" in *"Paired: yes"*) paired=yes ;; esac
  case "$info" in *"Trusted: yes"*) trusted=yes ;; esac
  if [ "$paired" = yes ] && [ "$trusted" = yes ]; then printf 'paired / trusted'
  elif [ "$paired" = yes ]; then printf 'paired'
  else printf 'new'; fi
}

bt_list() {
  bluetoothctl devices 2>/dev/null | sed 's/^Device //' | while IFS= read -r line; do
    mac=${line%% *}
    name=${line#* }
    [ -z "$mac" ] && continue
    printf '  %s  (%s / %s)\n' "$name" "$(bt_state "$mac")" "$mac"
  done
}

bt_menu() {
  powered=$(bt_powered)
  [ -z "$powered" ] && powered=unknown

  bluetoothctl power on >/dev/null 2>&1
  bluetoothctl --timeout 4 scan on >/dev/null 2>&1

  choice=$(printf '%s\n%s\n' \
    "  refresh" \
    "  power ($powered)" \
    "  pair by mac" \
    | { cat; bt_list; } \
    | menu "Bluetooth")

  case "$choice" in
    "")          exit 0 ;;
    *refresh*)   bt_menu ;;
    *power*)
      if [ "$powered" = yes ]; then bluetoothctl power off; else bluetoothctl power on; fi
      refresh_waybar; bt_menu ;;
    *"pair by mac"*)
      mac=$(ask "device mac address"); [ -z "$mac" ] && bt_menu
      bluetoothctl pair "$mac" >/dev/null 2>&1
      bluetoothctl trust "$mac" >/dev/null 2>&1
      bluetoothctl connect "$mac" >/dev/null 2>&1
      refresh_waybar; bt_menu ;;
    *)
      # A device row: "  name  (state / MAC)". Pull the trailing MAC.
      mac=$(printf '%s' "$choice" | sed -E 's/.* \/ ([0-9A-Fa-f:]+)\)$/\1/')
      state=$(bt_state "$mac")
      if [ "$state" = "connected" ]; then
        bluetoothctl disconnect "$mac" >/dev/null 2>&1
      else
        bluetoothctl connect "$mac" >/dev/null 2>&1
      fi
      refresh_waybar; bt_menu ;;
  esac
}

# ------------------------------------------------------------------ main

if [ "$PAGE" = "bluetooth" ]; then
  bt_menu
else
  wifi_menu
fi
