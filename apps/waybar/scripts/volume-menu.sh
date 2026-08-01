#!/usr/bin/env bash

# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../scripts" && pwd)/_paths.sh"
choice=$(printf '%s
' "Mute/Unmute" "Set 10%" "Set 20%" "Set 50%" "Set 100%" "Cancel" | rofi -dmenu -p "Volume" -theme-str 'window { width: 20em; }')
case "$choice" in
  "Mute/Unmute") pamixer -t;;
  "Set 10%") pamixer --set-volume 10;;
  "Set 20%") pamixer --set-volume 20;;
  "Set 50%") pamixer --set-volume 50;;
  "Set 100%") pamixer --set-volume 100;;
  *) exit 0;;
esac
