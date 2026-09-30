#!/usr/bin/env bash
#
# Waybar wifi/ethernet module. Shows an ethernet glyph when a wired
# connection is up, otherwise the connected SSID. Click opens
# nm-connection-editor. Pure shell.
#
# The click menu is *streamed* into rofi rather than collected first. rofi
# paints as soon as the first rows land on its stdin, so the dropdown is on
# screen immediately and the scan results fill in underneath it.


# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

ethernet_iface() {
  nmcli -t -f device,type,state device status 2>/dev/null \
    | awk -F: '$2=="ethernet" && $3=="connected"{print $1; exit}'
}

# Read the active *connection*, not the AP scan list. `dev wifi` reports from
# the scan cache, which intermittently drops the connected AP while a scan is
# in flight — that made the bar flip to "not connected" every few polls.
current_ssid() {
  timeout 2 nmcli -t -f NAME,TYPE connection show --active 2>/dev/null \
    | awk -F: '$2 ~ /wireless/ {print $1; exit}'
}

THEME="${HYPR_ROFI}/dropdown-right.rasi"

# rofi helpers, all anchored top-right via the dropdown theme.
rmenu()  { rofi -dmenu -i -theme "$THEME" -p "$1"; }
rinput() { rofi -dmenu -theme "$THEME" -p "$1" -theme-str 'listview { enabled: false; }'; }
rpass()  { rofi -dmenu -password -theme "$THEME" -p "$1" -theme-str 'listview { enabled: false; }'; }
rnotify(){ command -v notify-send >/dev/null 2>&1 && notify-send -a "Wi-Fi" "$1" "$2"; }

# Non-network rows. The case statement at the bottom ignores them, so a
# stray Enter on one does nothing.
HEADER="─────  Actions  ─────"
SCANNING="󰑓  Scanning for networks…"
FOUND="─────  Networks  ─────"
EMPTY="─────  No networks found  ─────"

# "unknown" when NetworkManager is too slow to answer; the caller treats that
# as "probably on" instead of showing a wrong "Wi-Fi off" prompt.
wifi_radio() {
  out=$(timeout 2 nmcli -t -f WIFI radio wifi 2>/dev/null)
  [ $? -eq 124 ] && { printf 'unknown'; return; }
  printf '%s' "$out"
}

# Build the network list: active network first (marked), then the rest by
# signal strength, de-duplicated by SSID.
# --rescan no is what makes this instant: NetworkManager hands back the last
# scan it has instead of blocking for a fresh one (several seconds when the
# cached results have gone stale).
list_networks() {
  timeout 3 nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list --rescan no 2>/dev/null \
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

# Map a block of formatted rows to their bare SSIDs, one per line.
# row_to_ssid deliberately prints without a newline, so add one here.
rows_to_ssids() {
  printf '%s\n' "$1" | while IFS= read -r row; do
    [ -z "$row" ] && continue
    printf '%s\n' "$(row_to_ssid "$row")"
  done
}

# Two passes over one pipe. Pass one prints whatever NetworkManager already
# knows, so rofi has something to draw on straight away; pass two waits on the
# background rescan and appends whatever it turned up. rofi is already open and
# interactive the whole time, and grows as rows arrive.
stream_menu() {
  header=$1; actions=$2
  seen=""

  nets=$(list_networks)
  if [ -n "$nets" ]; then
    printf '%s\n' "$nets"
    seen=$(rows_to_ssids "$nets")
  else
    printf '%s\n' "$SCANNING"
  fi
  cold=${nets:+0}; cold=${cold:-1}
  printf '%s\n%s\n' "$header" "$actions"

  # Results trickle in as the rescan progresses, so poll a few times. A write
  # to a closed pipe (user already picked something) kills this subshell.
  divider=0
  for _ in 1 2 3; do
    sleep 2
    fresh=$(list_networks)
    [ -z "$fresh" ] && continue
    new=$(printf '%s\n' "$fresh" | while IFS= read -r row; do
            [ -z "$row" ] && continue
            ssid=$(row_to_ssid "$row")
            printf '%s\n' "$seen" | grep -Fxq "$ssid" || printf '%s\n' "$row"
          done)
    [ -z "$new" ] && continue
    [ "$divider" -eq 0 ] && { printf '%s\n' "$FOUND"; divider=1; }
    printf '%s\n' "$new"
    seen=$(printf '%s\n%s\n' "$seen" "$(rows_to_ssids "$new")")
  done

  # Started cold and the rescan turned up nothing: retire the placeholder
  # with a real answer rather than leaving "Scanning…" on screen.
  [ "$cold" -eq 1 ] && [ "$divider" -eq 0 ] && printf '%s\n' "$EMPTY"
  return 0
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
  if [ "$radio" != "enabled" ] && [ "$radio" != "unknown" ]; then
    choice=$(printf '%s\n' "󰖩  Turn Wi-Fi on" "  Close" | rmenu "Wi-Fi off")
    case "$choice" in
      *"Turn Wi-Fi on"*) nmcli radio wifi on ;;
    esac
    exit 0
  fi

  nmcli device wifi rescan >/dev/null 2>&1 &
  current=$(current_ssid)
  header="$HEADER"
  actions=$(printf '%s\n' \
    "󰑓  Rescan networks" \
    "󰀂  Hotspot…" \
    "󰖪  Turn Wi-Fi off" \
    "󰒓  Advanced settings")

  choice=$(stream_menu "$header" "$actions" \
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
    "$SCANNING"|"$FOUND"|"$EMPTY") : ;;     # placeholder / divider, ignore
    "")       : ;;
    *)
      ssid=$(row_to_ssid "$choice")
      [ -n "$ssid" ] && connect_ssid "$ssid" ;;
  esac
  exit 0
fi

# Bar output is the glyph alone — what is actually connected lives in the
# hover tooltip, and the details/menu live in the quickshell control centre.
eth=$(ethernet_iface)
if [ -n "$eth" ]; then
  printf '{"text":"󰈀","tooltip":"Ethernet \u00b7 %s","class":"ethernet"}\n' "$(json_escape "$eth")"
  exit 0
fi

active=$(current_ssid)
if [ -n "$active" ]; then
  active_json=$(json_escape "$active")
  printf '{"text":"󰤨","tooltip":"Wi-Fi \u00b7 %s","class":"wifi"}\n' "$active_json"
else
  printf '{"text":"󰤮","tooltip":"Wi-Fi \u00b7 not connected","class":"disconnected"}\n'
fi
