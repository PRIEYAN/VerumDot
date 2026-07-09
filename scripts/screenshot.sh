#!/usr/bin/env bash
# Screenshot helper that works with whatever capture tool is installed.
# Usage: screenshot.sh take  -> region select (default)
#        screenshot.sh full  -> whole screen
# Saves to ~/Pictures/Screenshots and copies to the clipboard.

dir="$HOME/Pictures/Screenshots"
mkdir -p "$dir"
out="$dir/screenshot-$(date +%Y%m%d-%H%M%S).png"
mode="${1:-take}"

notify() { command -v notify-send >/dev/null 2>&1 && notify-send "Screenshot" "$1"; }

if command -v grimblast >/dev/null 2>&1; then
  case "$mode" in
    full) grimblast --notify copysave screen "$out" ;;
    *)    grimblast --notify copysave area   "$out" ;;
  esac
elif command -v hyprshot >/dev/null 2>&1; then
  case "$mode" in
    full) hyprshot -m output -o "$dir" -f "$(basename "$out")" ;;
    *)    hyprshot -m region -o "$dir" -f "$(basename "$out")" ;;
  esac
elif command -v grim >/dev/null 2>&1; then
  if [ "$mode" = "full" ]; then
    grim "$out"
  elif command -v slurp >/dev/null 2>&1; then
    grim -g "$(slurp)" "$out"
  else
    grim "$out"
  fi
  command -v wl-copy >/dev/null 2>&1 && wl-copy < "$out"
  notify "Saved $out"
else
  notify "No screenshot tool found (install grimblast or grim+slurp)"
  exit 1
fi
