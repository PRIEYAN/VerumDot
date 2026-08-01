#!/usr/bin/env bash
#
# Screenshots → ~/Pictures/Screenshots
#   full       entire screen (no area picker) — default
#   selection  pick a region with slurp
#
# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
set -euo pipefail

mode="${1:-full}"
dir="$HOME/Pictures/Screenshots"
mkdir -p "$dir"
file="$dir/screenshot-$(date +%Y%m%d-%H%M%S).png"

if ! command -v grim >/dev/null 2>&1; then
  notify-send "Screenshot" "Install grim first." 2>/dev/null || true
  exit 1
fi

case "$mode" in
  full|screen)
    grim "$file"
    ;;
  selection|area|region)
    if ! command -v slurp >/dev/null 2>&1; then
      notify-send "Screenshot" "Install slurp for area selection." 2>/dev/null || true
      exit 1
    fi
    geom="$(slurp)" || exit 0
    grim -g "$geom" "$file"
    ;;
  *)
    echo "Usage: $0 {full|selection}" >&2
    exit 1
    ;;
esac

if command -v wl-copy >/dev/null 2>&1; then
  wl-copy < "$file"
fi

notify-send "Screenshot saved" "$(basename "$file")" -i "$file" 2>/dev/null || true
