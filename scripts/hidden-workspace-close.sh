#!/usr/bin/env bash
#
# Close the hidden special workspace if it's open. Bound to the 4-finger
# swipe-down gesture; always allowed since you can only be here after
# opening it from workspace 1.
#
# The 3-finger horizontal swipe has no notion of "hidden workspace is
# open" and can silently change the regular workspace underneath while
# the hidden overlay stays on screen. Force workspace 1 on close so you
# always land back where you started, regardless of what happened below.

open=$(hyprctl -j monitors | python3 -c "
import json, sys
for m in json.load(sys.stdin):
    if m.get('focused'):
        print(m.get('specialWorkspace', {}).get('name', ''))
        break
")

if [[ "$open" == "special:hidden" ]]; then
  hyprctl dispatch togglespecialworkspace hidden
  hyprctl dispatch workspace 1
fi
