#!/usr/bin/env bash
# Sends a nav command (prev|next|today) to calendar-watch.sh via its FIFO.

fifo="${XDG_RUNTIME_DIR:-/tmp}/eww-calendar-center/nav.fifo"
[ -p "$fifo" ] && printf '%s\n' "$1" > "$fifo"
