#!/usr/bin/env bash
# Switches network-watch.sh's active page (wifi|bluetooth) and requests a
# rescan. Writes the page to the state file directly (so it applies even if
# the watcher hasn't started yet) and only pokes the FIFO if a reader exists,
# so this NEVER blocks — the caller's `; eww open network-center` always runs.

# self-locate so sibling scripts resolve for any user / checkout location
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
state_dir="${XDG_RUNTIME_DIR:-/tmp}/eww-network-center"
fifo="$state_dir/cmd.fifo"
page_file="$state_dir/page"
page="$1"

mkdir -p "$state_dir"
[ -p "$fifo" ] || mkfifo "$fifo"

# Authoritative page state — network-watch.sh reads this on startup and after
# each FIFO command.
printf '%s\n' "$page" > "$page_file"

# Non-blocking nudge: only write to the FIFO if something is reading it, and
# cap it with a timeout so a stale/reader-less FIFO can never hang the click.
if timeout 0.3 bash -c ': <>"'"$fifo"'"' 2>/dev/null; then
  timeout 0.3 bash -c 'printf "page:%s\n" "$1" > "$2"' _ "$page" "$fifo" 2>/dev/null &
fi

# Kick a rescan in the background so the list is fresh.
"$DIR/network-action.sh" "$page" rescan >/dev/null 2>&1 &

exit 0
