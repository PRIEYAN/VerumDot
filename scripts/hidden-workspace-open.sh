#!/usr/bin/env bash
#
# Open the hidden special workspace, but only when swiping up from
# workspace 1. Bound to the 4-finger swipe-up gesture.

# jq rather than python: jq is already a dependency and starts in ~5ms, which
# matters on a gesture binding.
state=$(hyprctl -j monitors | jq -r '
  map(select(.focused))[0]
  | if (.specialWorkspace.name // "") == "special:hidden"
    then "already-open"
    else (.activeWorkspace.name // "")
    end')

if [[ "$state" == "1" ]]; then
  hyprctl dispatch togglespecialworkspace hidden
fi
