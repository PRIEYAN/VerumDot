#!/usr/bin/env bash
# Long-running process for eww's (deflisten network_data ...). Emits JSON
# for whichever page (wifi|bluetooth) is currently selected, refreshing on
# a timer and whenever network-action.sh signals a state change.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/json.sh"

state_dir="${XDG_RUNTIME_DIR:-/tmp}/eww-network-center"
fifo="$state_dir/cmd.fifo"
page_file="$state_dir/page"
mkdir -p "$state_dir"
[ -p "$fifo" ] || mkfifo "$fifo"
[ -f "$page_file" ] || echo "wifi" > "$page_file"

# Build the wifi rows array (deduped by ssid). nmcli -t escapes ':' inside
# fields as '\:', so we split on unescaped colons by first protecting them.
wifi_rows() {
  local out="" line inuse ssid signal security active sec seen="|"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    # Protect escaped colons, split into the 4 fields, then restore.
    line=${line//\\:/$'\x01'}
    IFS=: read -r inuse ssid signal security <<< "$line"
    inuse=${inuse//$'\x01'/:}; ssid=${ssid//$'\x01'/:}
    signal=${signal//$'\x01'/:}; security=${security//$'\x01'/:}
    [ -n "$ssid" ] || continue
    case "$seen" in *"|$ssid|"*) continue ;; esac
    seen="$seen$ssid|"
    if [ "$inuse" = "*" ]; then active=true; else active=false; fi
    if [ -z "$security" ] || [ "$security" = "--" ]; then sec="open"; else sec="secured"; fi
    local cell
    cell=$(printf '{"active":%s,"ssid":%s,"signal":%s,"security":%s}' \
      "$active" "$(json_str "$ssid")" "$(json_str "$signal")" "$(json_str "$sec")")
    if [ -z "$out" ]; then out="$cell"; else out="$out,$cell"; fi
  done < <(nmcli -t -f in-use,ssid,signal,security dev wifi list 2>/dev/null)
  printf '[%s]' "$out"
}

wifi_json() {
  local current enabled rows hero_status powered
  current=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}')
  enabled=$(nmcli radio wifi 2>/dev/null)
  rows=$(wifi_rows)

  if [ -n "$current" ]; then hero_status="connected"; else hero_status=${enabled,,}; fi
  if [ "$enabled" = "enabled" ]; then powered=true; else powered=false; fi

  printf '{"page":"wifi","heroTitle":%s,"heroStatus":%s,"poweredOn":%s,"rows":%s}\n' \
    "$(json_str "${current:-wi-fi}")" "$(json_str "$hero_status")" "$powered" "$rows"
}

# Build the bluetooth rows array (deduped by mac).
bt_rows() {
  local out="" line rest mac name info state seen="|"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    # Lines look like: "Device AA:BB:CC:DD:EE:FF Some Name"
    rest=${line#Device }
    mac=${rest%% *}
    name=${rest#* }
    [ -n "$mac" ] || continue
    [ "$name" = "$rest" ] && continue   # no space → malformed, skip
    case "$seen" in *"|$mac|"*) continue ;; esac
    seen="$seen$mac|"
    info=$(bluetoothctl info "$mac" 2>/dev/null)
    if printf '%s' "$info" | grep -q 'Connected: yes'; then
      state="connected"
    elif printf '%s' "$info" | grep -q 'Paired: yes' && printf '%s' "$info" | grep -q 'Trusted: yes'; then
      state="paired / trusted"
    elif printf '%s' "$info" | grep -q 'Paired: yes'; then
      state="paired"
    else
      state="new"
    fi
    local cell
    cell=$(printf '{"mac":%s,"name":%s,"state":%s}' \
      "$(json_str "$mac")" "$(json_str "$name")" "$(json_str "$state")")
    if [ -z "$out" ]; then out="$cell"; else out="$out,$cell"; fi
  done < <(bluetoothctl devices 2>/dev/null)
  printf '[%s]' "$out"
}

bt_json() {
  local connected powered rows hero_status powered_bool
  connected=$(bluetoothctl devices Connected 2>/dev/null | head -n1 | sed 's/^Device [^ ]* //')
  powered=$(bluetoothctl show 2>/dev/null | awk '/Powered:/ {print $2; exit}')
  rows=$(bt_rows)

  if [ -n "$connected" ]; then
    hero_status="connected"
  elif [ "$powered" = "yes" ]; then
    hero_status="on"
  else
    hero_status="off"
  fi
  if [ "$powered" = "yes" ]; then powered_bool=true; else powered_bool=false; fi

  printf '{"page":"bluetooth","heroTitle":%s,"heroStatus":%s,"poweredOn":%s,"rows":%s}\n' \
    "$(json_str "${connected:-bluetooth}")" "$(json_str "$hero_status")" "$powered_bool" "$rows"
}

emit() {
  local page
  page=$(cat "$page_file")
  if [ "$page" = "bluetooth" ]; then bt_json; else wifi_json; fi
}

emit

while read -r cmd < "$fifo"; do
  case "$cmd" in
    page:wifi) echo "wifi" > "$page_file" ;;
    page:bluetooth) echo "bluetooth" > "$page_file" ;;
  esac
  emit
done
