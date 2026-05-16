#!/usr/bin/env bash
set -euo pipefail

wallpaper="$HOME/wallpapers/current.jpg"
if [[ -f "$wallpaper" ]]; then
  hyprpaper wallpaper "$wallpaper"
else
  echo "Wallpaper not found: $wallpaper" >&2
fi
