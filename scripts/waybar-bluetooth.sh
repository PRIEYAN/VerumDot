#!/usr/bin/env bash
# Bluetooth module for waybar, and its click-through dropdown.
#
#   (no args)  emit the waybar module JSON
#   menu       open the device dropdown
#
# Devices are keyed by MAC throughout. The old menu rendered a label, then
# recovered the device by reverse-parsing that label back to a name and
# looking the name up again — which broke for two devices sharing a name and
# for any name containing the separator it split on.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/cli ui/waybar ui/rofi ui/menu ui/notify domain/bluetooth

readonly THEME=dropdown-right
readonly ICON_CONNECTED='󰂱'
readonly ICON_ON='󰂯'
readonly ICON_OFF='󰂲'

readonly LOADING='󰑓  Loading devices…'
readonly NO_DEVICES='─────  No paired devices  ─────'

readonly ACTION_PAIR='󰂰  Scan & pair new device'
readonly ACTION_OFF='󰂲  Turn Bluetooth off'
readonly ACTION_MANAGER='󰒓  Bluetooth manager'

# ---------------------------------------------------------------------------
# Bar
# ---------------------------------------------------------------------------
cmd_status() {
  local powered connected
  if ! bluetooth::available; then
    waybar::emit "$ICON_OFF" 'bluetoothctl missing — install bluez-utils' off
    return 0
  fi

  powered=$(bluetooth::powered)
  connected=$(bluetooth::connected_names | head -n 1)

  if [[ -n $connected ]]; then
    waybar::emit "$ICON_CONNECTED" "Bluetooth · ${connected}" connected
  elif [[ $powered == yes ]]; then
    waybar::emit "$ICON_ON" 'Bluetooth · on, nothing connected' on
  elif [[ $powered == unknown ]]; then
    # bluetoothd did not answer in time; "starting up" is honest where
    # "off" would be a guess.
    waybar::emit "$ICON_ON" 'Bluetooth · starting up' on
  else
    waybar::emit "$ICON_OFF" 'Bluetooth · off' off
  fi
}

# ---------------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------------
device_rows() {
  local mac name state icon suffix
  while IFS=$'\t' read -r mac name state; do
    [[ -z $mac ]] && continue
    if [[ $state == connected ]]; then
      icon=$ICON_CONNECTED; suffix='  ·  connected  ✓'
    else
      icon=$ICON_OFF;       suffix='  ·  paired'
    fi
    menu::row "$mac" "$(printf '%s  %s%s' "$icon" "$name" "$suffix")"
  done < <(bluetooth::devices)
}

toggle_device() {
  local mac=$1 name=$2
  if bluetooth::is_connected "$mac"; then
    bluetooth::disconnect "$mac"
    notify::info 'Disconnected' "$name"
  elif bluetooth::connect "$mac"; then
    notify::info 'Connected' "$name"
  else
    notify::warn 'Connect failed' "$name"
  fi
}

scan_and_pair() {
  local choice mac rows
  notify::info 'Scanning…' 'Looking for nearby Bluetooth devices'
  bluetooth::scan

  mapfile -t rows < <(device_rows)
  (( ${#rows[@]} )) || { notify::warn 'No devices found' 'Try again'; return 0; }

  choice=$(printf '%s\n' "${rows[@]}" | menu::labels | rofi::menu "$THEME" 'Pair device')
  [[ -z $choice ]] && return 0
  mac=$(menu::key_for "$choice" "${rows[@]}") || return 0

  if bluetooth::pair "$mac"; then
    notify::info 'Connected' "$choice"
  else
    notify::info 'Paired' "${choice} (not connected)"
  fi
}

cmd_menu() {
  bluetooth::available || { notify::warn 'bluetoothctl missing' 'Install bluez-utils'; return 0; }
  rofi::available      || log::die 'rofi is not installed'

  local powered choice mac rows
  powered=$(bluetooth::powered)
  # As with the Wi-Fi radio, "unknown" is "probably on", not "off".
  if [[ $powered != yes && $powered != unknown ]]; then
    choice=$(printf '%s\n' '󰂯  Turn Bluetooth on' '  Close' | rofi::menu "$THEME" 'Bluetooth off')
    [[ $choice == *'Turn Bluetooth on'* ]] && bluetooth::power_on
    return 0
  fi

  choice=$(menu::stream device_rows 3 2 "$LOADING" "$NO_DEVICES" \
             "$(rofi::divider Actions)" \
             "$ACTION_PAIR" "$ACTION_OFF" "$ACTION_MANAGER" \
           | menu::labels \
           | rofi::menu "$THEME" 'Bluetooth')

  [[ -z $choice ]] && return 0
  rofi::is_divider "$choice" && return 0

  case $choice in
    "$ACTION_PAIR")    scan_and_pair ;;
    "$ACTION_OFF")     bluetooth::power_off ;;
    "$ACTION_MANAGER") bluetooth::open_manager ;;
    "$LOADING"|"$NO_DEVICES") ;;
    *)
      mapfile -t rows < <(device_rows)
      mac=$(menu::key_for "$choice" "${rows[@]}") || return 0
      toggle_device "$mac" "$choice"
      ;;
  esac
}

declare -A COMMANDS=(
  [status]="cmd_status|emit the waybar module JSON (the default)"
  [menu]="cmd_menu|open the Bluetooth dropdown"
)

cli::dispatch "${1:-status}" "${@:2}"
