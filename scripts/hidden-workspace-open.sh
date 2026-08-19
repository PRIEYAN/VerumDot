#!/usr/bin/env bash
#
# Open the hidden special workspace, but only when swiping up from
# workspace 1. Bound to the 4-finger swipe-up gesture.

state=$(hyprctl -j monitors | python3 -c "
import json, sys
for m in json.load(sys.stdin):
    if m.get('focused'):
        active = m.get('activeWorkspace', {}).get('name', '')
        special = m.get('specialWorkspace', {}).get('name', '')
        print('already-open' if special == 'special:hidden' else active)
        break
")

if [[ "$state" == "1" ]]; then
  hyprctl dispatch togglespecialworkspace hidden
fi
