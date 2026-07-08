#!/usr/bin/env bash
# Long-running process for eww's (deflisten network_data ...). Emits JSON
# for whichever page (wifi|bluetooth) is currently selected, refreshing on
# a timer and whenever network-action.sh signals a state change.

state_dir="/tmp/eww-network-center"
fifo="$state_dir/cmd.fifo"
page_file="$state_dir/page"
mkdir -p "$state_dir"
[ -p "$fifo" ] || mkfifo "$fifo"
[ -f "$page_file" ] || echo "wifi" > "$page_file"

wifi_json() {
  local current enabled
  current=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}')
  enabled=$(nmcli radio wifi 2>/dev/null)

  local rows="[]"
  rows=$(nmcli -t -f in-use,ssid,signal,security dev wifi list 2>/dev/null | python3 -c "
import json, sys
seen = set()
rows = []
for line in sys.stdin:
    parts = line.rstrip('\n').split(':', 3)
    if len(parts) < 4 or not parts[1] or parts[1] in seen:
        continue
    seen.add(parts[1])
    rows.append({
        'active': parts[0] == '*',
        'ssid': parts[1],
        'signal': parts[2],
        'security': 'open' if parts[3] in ('', '--') else 'secured',
    })
print(json.dumps(rows))
")

  python3 -c "
import json
print(json.dumps({
    'page': 'wifi',
    'heroTitle': '''$current''' or 'wi-fi',
    'heroStatus': 'connected' if '''$current''' else '''$enabled'''.lower(),
    'poweredOn': '''$enabled''' == 'enabled',
    'rows': json.loads('''$rows'''),
}))
"
}

bt_json() {
  local connected powered
  connected=$(bluetoothctl devices Connected 2>/dev/null | head -n1 | sed 's/^Device [^ ]* //')
  powered=$(bluetoothctl show 2>/dev/null | awk '/Powered:/ {print $2; exit}')

  local rows
  rows=$(bluetoothctl devices 2>/dev/null | python3 -c "
import json, subprocess, sys
seen = set()
rows = []
for line in sys.stdin:
    rest = line.rstrip('\n').replace('Device ', '', 1)
    parts = rest.split(' ', 1)
    if len(parts) < 2 or parts[0] in seen:
        continue
    seen.add(parts[0])
    mac, name = parts
    info = subprocess.run(['bluetoothctl', 'info', mac], capture_output=True, text=True).stdout
    if 'Connected: yes' in info:
        state = 'connected'
    elif 'Paired: yes' in info and 'Trusted: yes' in info:
        state = 'paired / trusted'
    elif 'Paired: yes' in info:
        state = 'paired'
    else:
        state = 'new'
    rows.append({'mac': mac, 'name': name, 'state': state})
print(json.dumps(rows))
")

  python3 -c "
import json
connected = '''$connected'''
print(json.dumps({
    'page': 'bluetooth',
    'heroTitle': connected or 'bluetooth',
    'heroStatus': 'connected' if connected else ('on' if '''$powered''' == 'yes' else 'off'),
    'poweredOn': '''$powered''' == 'yes',
    'rows': json.loads('''$rows'''),
}))
"
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
