#!/usr/bin/env bash
# Sends a new search query to wallpaper-watch.sh via its FIFO.

fifo="${XDG_RUNTIME_DIR:-/tmp}/eww-wallpaper-center/query.fifo"
[ -p "$fifo" ] && printf '%s\n' "$1" > "$fifo"
