#!/usr/bin/env bash
# Long-running process for eww's (deflisten wallpaper_data ...). Emits one
# JSON line whenever wallpaper-search.sh signals a new filter via the FIFO.

state_dir="/tmp/eww-wallpaper-center"
fifo="$state_dir/query.fifo"
mkdir -p "$state_dir"
[ -p "$fifo" ] || mkfifo "$fifo"

/home/prieyan/.config/hypr/scripts/wallpaper-list.sh ""

while read -r query < "$fifo"; do
  /home/prieyan/.config/hypr/scripts/wallpaper-list.sh "$query"
done
