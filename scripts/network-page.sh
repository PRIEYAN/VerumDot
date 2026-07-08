#!/usr/bin/env bash
# Switches network-watch.sh's active page (wifi|bluetooth) and requests a
# rescan, so opening a tab always shows fresh data.

fifo="/tmp/eww-network-center/cmd.fifo"
page="$1"
mkdir -p /tmp/eww-network-center
[ -p "$fifo" ] || mkfifo "$fifo"
printf 'page:%s\n' "$page" > "$fifo"
/home/prieyan/.config/hypr/scripts/network-action.sh "$page" rescan &
