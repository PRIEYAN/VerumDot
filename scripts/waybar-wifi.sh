#!/usr/bin/env bash
#
# Waybar wifi/ethernet module. Shows an ethernet glyph when a wired
# connection is up, otherwise the connected SSID. Click opens
# nm-connection-editor. Pure shell.

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

ethernet_iface() {
  nmcli -t -f device,type,state device status 2>/dev/null \
    | awk -F: '$2=="ethernet" && $3=="connected"{print $1; exit}'
}

current_ssid() {
  nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}'
}

THEME=/home/prieyan/.config/hypr/apps/rofi/dropdown-right.rasi

# rofi helpers, all anchored top-right via the dropdown theme.
rmenu()  { rofi -dmenu -i -theme "$THEME" -p "$1"; }
rinput() { rofi -dmenu -theme "$THEME" -p "$1" -theme-str 'listview { enabled: false; }'; }
rpass()  { rofi -dmenu -password -theme "$THEME" -p "$1" -theme-str 'listview { enabled: false; }'; }
rnotify(){ command -v notify-send >/dev/null 2>&1 && notify-send -a "Wi-Fi" "$1" "$2"; }

wifi_radio() { nmcli -t -f WIFI radio wifi 2>/dev/null; }

# Build the network list: active network first (marked), then the rest by
# signal strength, de-duplicated by SSID.
list_networks() {
  nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list 2>/dev/null \
    | awk -F: '
        $4 == "" { next }                        # skip hidden/blank SSIDs
        !seen[$4]++ {
          inuse = ($1 == "*")
          lock  = ($3 == "" || $3 == "--") ? "" : ""
          mark  = inuse ? "󰤨 " : "󰤥 "
          star  = inuse ? "  ✓" : ""
          printf "%s%s%s  ·  %s%%%s\n", mark, $4, (lock=="" ? "" : " "lock), $2, star
        }'
}

# Extract the SSID back out of a formatted list row.
row_to_ssid() {
  printf '%s' "$1" | sed -E 's/^[^ ]+ //; s/  ·.*$//; s/ $//'
}

connect_ssid() {
  ssid=$1
  # Known/saved connection: just bring it up.
  if nmcli -t -f NAME connection show 2>/dev/null | grep -Fxq "$ssid"; then
    if nmcli connection up id "$ssid" >/dev/null 2>&1; then
      rnotify "Connected" "$ssid"; return
    fi
  fi
  # Try open connect first; if it needs a secret, prompt for a password.
  if nmcli device wifi connect "$ssid" >/dev/null 2>&1; then
    rnotify "Connected" "$ssid"; return
  fi
  pass=$(rpass "Password for $ssid")
  [ -z "$pass" ] && return
  if nmcli device wifi connect "$ssid" password "$pass" >/dev/null 2>&1; then
    rnotify "Connected" "$ssid"
  else
    rnotify "Connection failed" "$ssid"
  fi
}

if [ "$1" = "menu" ]; then
  radio=$(wifi_radio)
  if [ "$radio" != "enabled" ]; then
    choice=$(printf '%s\n' "󰖩  Turn Wi-Fi on" "  Close" | rmenu "Wi-Fi off")
    case "$choice" in
      *"Turn Wi-Fi on"*) nmcli radio wifi on ;;
    esac
    exit 0
  fi

  nmcli device wifi rescan >/dev/null 2>&1 &
  current=$(current_ssid)
  header="─────  Actions  ─────"
  actions=$(printf '%s\n' \
    "󰑓  Rescan networks" \
    "󰀂  Hotspot…" \
    "󰖪  Turn Wi-Fi off" \
    "󰒓  Advanced settings")

  nets=$(list_networks)
  choice=$(printf '%s\n%s\n%s' "$nets" "$header" "$actions" \
             | rmenu "Wi-Fi${current:+ ($current)}")
  [ -z "$choice" ] && exit 0

  case "$choice" in
    *"Rescan networks"*)
      nmcli device wifi rescan >/dev/null 2>&1
      exec "$0" menu ;;
    *"Turn Wi-Fi off"*)
      nmcli radio wifi off ;;
    *"Advanced settings"*)
      setsid -f nm-connection-editor >/dev/null 2>&1 ;;
    *"Hotspot"*)
      name=$(rinput "Hotspot name")
      [ -z "$name" ] && exit 0
      pass=$(rpass "Hotspot password (min 8 chars)")
      [ -z "$pass" ] && exit 0
      if nmcli device wifi hotspot ssid "$name" password "$pass" >/dev/null 2>&1; then
        rnotify "Hotspot started" "$name"
      else
        rnotify "Hotspot failed" "Check the password length (min 8)."
      fi ;;
    "$header") : ;;                         # divider, ignore
    "")       : ;;
    *)
      ssid=$(row_to_ssid "$choice")
      [ -n "$ssid" ] && connect_ssid "$ssid" ;;
  esac
  exit 0
fi

eth=$(ethernet_iface)
if [ -n "$eth" ]; then
  # Wired connection: ethernet glyph + label.
  printf '{"text":"󰈀 Ethernet","tooltip":"Ethernet connected (%s)","class":"ethernet"}\n' "$(json_escape "$eth")"
  exit 0
fi

active=$(current_ssid)
if [ -n "$active" ]; then
  active_json=$(json_escape "$active")
  printf '{"text":"󰤨 %s","tooltip":"Wi-Fi: %s","class":"wifi"}\n' "$active_json" "$active_json"
else
  printf '{"text":"󰤮","tooltip":"Wi-Fi: not connected","class":"disconnected"}\n'
fi
