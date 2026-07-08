#!/usr/bin/env bash
set -euo pipefail
# Screenshot helper. Usage:
#   screenshot.sh take    -> region-select capture (default)
#   screenshot.sh full    -> whole-screen capture
# Saves to ~/Pictures/Screenshots and copies to the clipboard.

dir="$HOME/Pictures/Screenshots"
mkdir -p "$dir"
out="$dir/screenshot-$(date +%Y%m%d-%H%M%S).png"

case "${1:-take}" in
  full) grimblast --notify copysave screen "$out" ;;
  take|*) grimblast --notify copysave area "$out" ;;
esac
