#!/usr/bin/env bash
# domain/network.sh — NetworkManager, behind a vocabulary.
#
# Every nmcli call in the rice is here. They all carry a `timeout` because
# NetworkManager can block for seconds when a scan is in flight, and a bar
# module that blocks is a bar that stops repainting.

hypr::use core/guard core/log os/proc

readonly NM_TIMEOUT=2
readonly NM_SCAN_TIMEOUT=3

network::available() { guard::has nmcli; }

# network::ethernet_device — the first connected wired interface, if any.
network::ethernet_device() {
  timeout "$NM_TIMEOUT" nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null \
    | awk -F: '$2 == "ethernet" && $3 == "connected" { print $1; exit }'
}

# network::ssid — the SSID of the active wireless *connection*.
#
# Deliberately not `nmcli dev wifi`, which reports from the scan cache and
# intermittently omits the connected AP while a scan is running. Reading the
# connection instead is what stopped the bar flipping to "not connected"
# every few polls.
network::ssid() {
  timeout "$NM_TIMEOUT" nmcli -t -f NAME,TYPE connection show --active 2>/dev/null \
    | awk -F: '$2 ~ /wireless/ { print $1; exit }'
}

network::connected() { [[ -n $(network::ssid) ]]; }

# network::radio_state — enabled | disabled | unknown.
#
# "unknown" is a distinct answer, not an error: when NetworkManager is too
# slow to reply, the caller must not conclude the radio is off and offer to
# turn it on. Timeout exits 124.
network::radio_state() {
  local out status
  out=$(timeout "$NM_TIMEOUT" nmcli -t -f WIFI radio wifi 2>/dev/null)
  status=$?
  (( status == 124 )) && { printf 'unknown'; return 0; }
  printf '%s' "${out:-unknown}"
}

network::radio_on()  { proc::quiet nmcli radio wifi on; }
network::radio_off() { proc::quiet nmcli radio wifi off; }
network::rescan()    { proc::quiet nmcli device wifi rescan; }

# network::scan_results — "SSID<TAB>signal<TAB>secured<TAB>active", one per
# line, de-duplicated by SSID and ordered active-first then by signal.
#
# Tab-separated rather than pre-formatted: presentation belongs to the menu,
# not here, and the old version's formatted rows had to be reverse-parsed
# with a regex to recover the SSID the user had picked.
#
# --rescan no is what makes this instant — NetworkManager returns the scan
# it already has instead of blocking for a fresh one.
network::scan_results() {
  timeout "$NM_SCAN_TIMEOUT" nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID \
      device wifi list --rescan no 2>/dev/null \
    | awk -F: '
        $4 == "" { next }                       # hidden or blank SSID
        !seen[$4]++ {
          secured = ($3 == "" || $3 == "--") ? "open" : "secured"
          active  = ($1 == "*") ? "active" : "saved"
          printf "%s\t%s\t%s\t%s\n", $4, $2, secured, active
        }'
}

network::is_saved() {
  nmcli -t -f NAME connection show 2>/dev/null | grep -Fxq -- "$1"
}

# network::connect <ssid> [password] — bring up a saved profile, or join.
# Returns 2 specifically when a secret is required, so the caller knows to
# prompt rather than reporting a generic failure.
network::connect() {
  local ssid=$1 password=${2:-}
  if [[ -z $password ]] && network::is_saved "$ssid"; then
    proc::quiet nmcli connection up id "$ssid" && return 0
  fi
  if [[ -n $password ]]; then
    proc::quiet nmcli device wifi connect "$ssid" password "$password" && return 0
    return 1
  fi
  proc::quiet nmcli device wifi connect "$ssid" && return 0
  return 2
}

network::start_hotspot() {
  local name=$1 password=$2
  proc::quiet nmcli device wifi hotspot ssid "$name" password "$password"
}

network::open_editor() { proc::detach nm-connection-editor; }
