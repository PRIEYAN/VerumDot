#!/usr/bin/env bash
# Wi-Fi / Ethernet module for waybar, and its click-through dropdown.
#
#   (no args)  emit the waybar module JSON
#   menu       open the network dropdown
#
# The bar shows the glyph alone; what is connected lives in the tooltip and
# the full detail lives in the quickshell control centre.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/cli ui/waybar ui/rofi ui/menu ui/notify domain/network

readonly THEME=dropdown-right
readonly ICON_ETHERNET='󰈀'
readonly ICON_CONNECTED='󰤨'
readonly ICON_OFFLINE='󰤮'
readonly ICON_SIGNAL='󰤥'
readonly ICON_LOCK=''

readonly SCANNING='󰑓  Scanning for networks…'
readonly NO_NETWORKS='─────  No networks found  ─────'

readonly ACTION_RESCAN='󰑓  Rescan networks'
readonly ACTION_HOTSPOT='󰀂  Hotspot…'
readonly ACTION_OFF='󰖪  Turn Wi-Fi off'
readonly ACTION_ADVANCED='󰒓  Advanced settings'

# ---------------------------------------------------------------------------
# Bar
# ---------------------------------------------------------------------------
cmd_status() {
  local ethernet ssid
  if ! network::available; then
    waybar::emit "$ICON_OFFLINE" 'NetworkManager is not installed' disconnected
    return 0
  fi

  ethernet=$(network::ethernet_device)
  if [[ -n $ethernet ]]; then
    waybar::emit "$ICON_ETHERNET" "Ethernet · ${ethernet}" ethernet
    return 0
  fi

  ssid=$(network::ssid)
  if [[ -n $ssid ]]; then
    waybar::emit "$ICON_CONNECTED" "Wi-Fi · ${ssid}" wifi
  else
    waybar::emit "$ICON_OFFLINE" 'Wi-Fi · not connected' disconnected
  fi
}

# ---------------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------------
# Rows are "SSID<TAB>label", so the SSID is carried rather than re-derived
# from the rendered label.
network_rows() {
  local ssid signal secured active mark star lock
  while IFS=$'\t' read -r ssid signal secured active; do
    [[ -z $ssid ]] && continue
    [[ $active == active ]] && { mark=$ICON_CONNECTED; star='  ✓'; } \
                            || { mark=$ICON_SIGNAL;    star=''; }
    [[ $secured == secured ]] && lock=" ${ICON_LOCK}" || lock=''
    menu::row "$ssid" "$(printf '%s  %s%s  ·  %s%%%s' "$mark" "$ssid" "$lock" "$signal" "$star")"
  done < <(network::scan_results)
}

join_network() {
  local ssid=$1 password status
  network::connect "$ssid"; status=$?
  case $status in
    0) notify::info 'Connected' "$ssid"; return 0 ;;
    2) ;;                                   # needs a secret, fall through
    *) notify::warn 'Connection failed' "$ssid"; return 1 ;;
  esac

  password=$(rofi::password "$THEME" "Password for ${ssid}")
  [[ -z $password ]] && return 0
  if network::connect "$ssid" "$password"; then
    notify::info 'Connected' "$ssid"
  else
    notify::warn 'Connection failed' "$ssid"
  fi
}

start_hotspot() {
  local name password
  name=$(rofi::input "$THEME" 'Hotspot name')
  [[ -z $name ]] && return 0
  password=$(rofi::password "$THEME" 'Hotspot password (min 8 chars)')
  [[ -z $password ]] && return 0
  if network::start_hotspot "$name" "$password"; then
    notify::info 'Hotspot started' "$name"
  else
    notify::warn 'Hotspot failed' 'Check the password length (min 8).'
  fi
}

cmd_menu() {
  network::available || log::die 'NetworkManager (nmcli) is not installed'
  rofi::available    || log::die 'rofi is not installed'

  local radio choice ssid rows
  radio=$(network::radio_state)
  # "unknown" means NetworkManager was too slow to answer — treat it as
  # probably-on rather than showing a wrong "Wi-Fi is off" prompt.
  if [[ $radio != enabled && $radio != unknown ]]; then
    choice=$(printf '%s\n' '󰖩  Turn Wi-Fi on' '  Close' | rofi::menu "$THEME" 'Wi-Fi off')
    [[ $choice == *'Turn Wi-Fi on'* ]] && network::radio_on
    return 0
  fi

  network::rescan &            # results trickle in while the menu is already up

  rows=$(network_rows)
  choice=$(menu::stream network_rows 3 2 "$SCANNING" "$NO_NETWORKS" \
             "$(rofi::divider Actions)" \
             "$ACTION_RESCAN" "$ACTION_HOTSPOT" "$ACTION_OFF" "$ACTION_ADVANCED" \
           | menu::labels \
           | rofi::menu "$THEME" "Wi-Fi$( [[ -n $(network::ssid) ]] && printf ' (%s)' "$(network::ssid)" )")

  [[ -z $choice ]] && return 0
  rofi::is_divider "$choice" && return 0

  case $choice in
    "$ACTION_RESCAN")   network::rescan; exec "$0" menu ;;
    "$ACTION_OFF")      network::radio_off ;;
    "$ACTION_ADVANCED") network::open_editor ;;
    "$ACTION_HOTSPOT")  start_hotspot ;;
    "$SCANNING"|"$NO_NETWORKS") ;;
    *)
      # Re-read the rows so a network that appeared mid-stream resolves too.
      mapfile -t rows < <(network_rows)
      ssid=$(menu::key_for "$choice" "${rows[@]}") || return 0
      [[ -n $ssid ]] && join_network "$ssid"
      ;;
  esac
}

declare -A COMMANDS=(
  [status]="cmd_status|emit the waybar module JSON (the default)"
  [menu]="cmd_menu|open the Wi-Fi dropdown"
)

cli::dispatch "${1:-status}" "${@:2}"
