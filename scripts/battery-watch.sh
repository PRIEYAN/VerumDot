#!/usr/bin/env bash
# Instant battery/charger refresh for waybar.
#
# Watches power events and repaints the battery module the moment AC is
# plugged or unplugged, so the charging bolt appears immediately instead of
# waiting out the module's poll interval. Falls back to polling the AC
# 'online' flag when upower is unavailable.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/guard ui/waybar

readonly POLL_SECONDS=2

repaint() { waybar::refresh battery; }

trap 'exit 0' TERM INT

# Once on start, so the bar is correct immediately after launch.
repaint

if guard::has upower; then
  # Each power event prints a line; any of them is worth a repaint, which
  # is cheap and rare.
  upower --monitor 2>/dev/null | while read -r _; do repaint; done
  exit 0
fi

adapter=$(find /sys/class/power_supply -maxdepth 1 \
  \( -name 'ADP*' -o -name 'AC*' -o -name 'ACAD*' \) -print -quit 2>/dev/null)

if [[ -z $adapter || ! -r "$adapter/online" ]]; then
  log::die -c 0 'no AC adapter to watch and upower is unavailable'
fi

last=''
while :; do
  current=$(<"$adapter/online")
  [[ $current != "$last" ]] && { repaint; last=$current; }
  sleep "$POLL_SECONDS"
done
