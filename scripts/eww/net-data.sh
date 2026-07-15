#!/usr/bin/env bash
#
# Network data backend for the eww panel. Pure shell.
# Emits JSON that eww polls. Usage:
#   net-data.sh state        -> {ethernet, wifi_enabled, ssid, ...}
#   net-data.sh known        -> JSON array of saved wifi networks
#   net-data.sh other        -> JSON array of nearby (unsaved) networks
#   net-data.sh bt-state     -> {powered, connected}
#   net-data.sh bt-devices   -> JSON array of bluetooth devices
#
# All output is JSON so eww can splice it directly into widgets.

json_str() {
  # Escape a value for embedding in a JSON string.
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# ---------------------------------------------------------------- wifi/eth

ethernet_iface() {
  # First connected wired device, if any.
  nmcli -t -f device,type,state device status 2>/dev/null \
    | awk -F: '$2=="ethernet" && $3=="connected"{print $1; exit}'
}

wifi_ssid() {
  nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}'
}

wifi_enabled() {
  nmcli radio wifi 2>/dev/null
}

state() {
  eth=$(ethernet_iface)
  ssid=$(wifi_ssid)
  radio=$(wifi_enabled)
  if [ -n "$eth" ]; then
    kind="ethernet"
  elif [ -n "$ssid" ]; then
    kind="wifi"
  else
    kind="none"
  fi
  printf '{"kind":"%s","ethernet":"%s","ssid":"%s","wifi_enabled":%s}\n' \
    "$kind" \
    "$(json_str "$eth")" \
    "$(json_str "$ssid")" \
    "$([ "$radio" = "enabled" ] && echo true || echo false)"
}

# Emit a JSON array of {ssid,signal,secured,active} from a filter.
# $1 = "known" (only saved) or "other" (only unsaved).
scan() {
  want=$1
  saved=$(nmcli -t -f name connection show 2>/dev/null)
  nmcli -t -f in-use,ssid,signal,security dev wifi list 2>/dev/null \
    | awk -F: -v want="$want" -v saved="$saved" '
      BEGIN {
        n = split(saved, arr, "\n")
        for (i = 1; i <= n; i++) issaved[arr[i]] = 1
        print "["
        first = 1
      }
      $2 != "" && !seen[$2]++ {
        ssid = $2
        known = (ssid in issaved) ? "true" : "false"
        if (want == "known" && known == "false") next
        if (want == "other" && known == "true") next
        sec = ($4 == "" || $4 == "--") ? "false" : "true"
        active = ($1 == "*") ? "true" : "false"
        gsub(/\\/, "\\\\", ssid); gsub(/"/, "\\\"", ssid)
        if (!first) printf ",\n"
        first = 0
        printf "  {\"ssid\":\"%s\",\"signal\":%s,\"secured\":%s,\"active\":%s}", ssid, $3, sec, active
      }
      END { print "\n]" }'
}

# ------------------------------------------------------------- bluetooth

bt_state() {
  powered=$(bluetoothctl show 2>/dev/null | awk '/Powered:/ {print $2; exit}')
  connected=$(bluetoothctl devices Connected 2>/dev/null | sed 's/^Device [^ ]* //' | head -n1)
  printf '{"powered":%s,"connected":"%s"}\n' \
    "$([ "$powered" = "yes" ] && echo true || echo false)" \
    "$(json_str "$connected")"
}

bt_devices() {
  printf '['
  first=1
  bluetoothctl devices 2>/dev/null | sed 's/^Device //' | while IFS= read -r line; do
    mac=${line%% *}
    name=${line#* }
    [ -z "$mac" ] && continue
    info=$(bluetoothctl info "$mac" 2>/dev/null)
    case "$info" in
      *"Connected: yes"*) st="connected" ;;
      *"Paired: yes"*)    st="paired" ;;
      *)                  st="new" ;;
    esac
    [ "$first" = 1 ] || printf ','
    first=0
    printf '{"mac":"%s","name":"%s","state":"%s"}' \
      "$(json_str "$mac")" "$(json_str "$name")" "$st"
  done
  printf ']\n'
}

case "$1" in
  state)      state ;;
  known)      scan known ;;
  other)      scan other ;;
  bt-state)   bt_state ;;
  bt-devices) bt_devices ;;
  *)          echo '{}' ;;
esac
