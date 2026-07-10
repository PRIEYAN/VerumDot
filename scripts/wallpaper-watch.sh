#!/usr/bin/env bash
# Long-running process for eww's (deflisten wallpaper_data ...). Emits one
# JSON line whenever wallpaper-search.sh signals a new filter via the FIFO.

# self-locate so sibling scripts resolve for any user / checkout location
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
state_dir="${XDG_RUNTIME_DIR:-/tmp}/eww-wallpaper-center"
fifo="$state_dir/query.fifo"
mkdir -p "$state_dir"
[ -p "$fifo" ] || mkfifo "$fifo"

"$DIR/wallpaper-list.sh" ""

while read -r query < "$fifo"; do
  "$DIR/wallpaper-list.sh" "$query"
done
