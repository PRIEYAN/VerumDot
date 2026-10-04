#!/usr/bin/env bash
# domain/bluetooth.sh — bluetoothctl, behind a vocabulary.
#
# Devices are identified by MAC throughout. The old menu rendered a row,
# then recovered the device by reverse-parsing the row text back to a name
# and looking the name up again — which broke for two devices sharing a name
# and for any name containing the separator it split on.

hypr::use core/guard core/log os/proc

readonly BT_TIMEOUT=2
readonly BT_LIST_TIMEOUT=5
readonly BT_SCAN_SECONDS=8

bluetooth::available() { guard::has bluetoothctl; }

# bluetooth::powered — yes | no | unknown.
# As with the Wi-Fi radio, "unknown" means bluetoothd did not answer in
# time and must not be reported to the user as "off".
bluetooth::powered() {
  local out status
  out=$(timeout "$BT_TIMEOUT" bluetoothctl show 2>/dev/null)
  status=$?
  (( status == 124 )) && { printf 'unknown'; return 0; }
  printf '%s' "$(awk '/Powered:/ { print $2; exit }' <<<"$out")"
}

bluetooth::power_on()  { proc::quiet bluetoothctl power on; }
bluetooth::power_off() { proc::quiet bluetoothctl power off; }

# bluetooth::connected_macs — one MAC per line.
bluetooth::connected_macs() {
  timeout "$BT_TIMEOUT" bluetoothctl devices Connected 2>/dev/null | awk '{ print $2 }'
}

bluetooth::connected_names() {
  timeout "$BT_TIMEOUT" bluetoothctl devices Connected 2>/dev/null \
    | sed 's/^Device [^ ]* //'
}

# bluetooth::devices — "MAC<TAB>name<TAB>connected|paired", one per line.
# The MAC leads so a caller can key on it without parsing a rendered label.
bluetooth::devices() {
  local connected mac name rest
  connected=$(bluetooth::connected_macs)
  timeout "$BT_LIST_TIMEOUT" bluetoothctl devices 2>/dev/null \
    | while read -r _ mac rest; do
        [[ -z $mac ]] && continue
        name=$rest
        if grep -Fxq -- "$mac" <<<"$connected"; then
          printf '%s\t%s\tconnected\n' "$mac" "$name"
        else
          printf '%s\t%s\tpaired\n' "$mac" "$name"
        fi
      done
}

bluetooth::is_connected() {
  grep -Fxq -- "$1" <<<"$(bluetooth::connected_macs)"
}

bluetooth::connect()    { proc::quiet bluetoothctl connect "$1"; }
bluetooth::disconnect() { proc::quiet bluetoothctl disconnect "$1"; }

# bluetooth::pair <mac> — pair, trust, then connect. Trusting is what stops
# the device asking to be re-authorised on every reconnection.
bluetooth::pair() {
  local mac=$1
  proc::quiet bluetoothctl pair "$mac"
  proc::quiet bluetoothctl trust "$mac"
  bluetooth::connect "$mac"
}

# bluetooth::scan — block for the scan window, then return. Discovered
# devices show up in bluetooth::devices afterwards.
bluetooth::scan() {
  proc::quiet bluetoothctl --timeout "$BT_SCAN_SECONDS" scan on
}

bluetooth::open_manager() { proc::detach blueman-manager; }
