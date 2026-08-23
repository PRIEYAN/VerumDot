#!/usr/bin/env bash
# Clock for waybar, with a red "hidden-ws" class while the focused monitor
# is showing the special:hidden workspace.
#
# Ticks once a second and also reacts to Hyprland events, emitting only when
# the rendered output actually changes.

hidden_ws_open() {
  hyprctl -j monitors 2>/dev/null \
    | jq -e 'any(.[]; .focused and (.specialWorkspace.name == "special:hidden"))' \
      >/dev/null 2>&1
}

render() {
  local cls=''
  hidden_ws_open && cls='hidden-ws'
  jq -nc --arg t "$(date '+%a %d %b  %H:%M')" \
         --arg tt "$(date '+%A, %d %B %Y  %H:%M:%S')" \
         --arg c "$cls" \
    '{text:$t, tooltip:$tt, class:(if $c == "" then [] else [$c] end)}'
}

last=''
emit() {
  local cur; cur=$(render)
  if [ "$cur" != "$last" ]; then printf '%s\n' "$cur"; last="$cur"; fi
}

socket2() {
  local dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr"
  if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] \
     && [ -S "$dir/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" ]; then
    printf '%s' "$dir/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
    return 0
  fi
  ls -1t "$dir"/*/.socket2.sock 2>/dev/null | head -1
}

trap 'exit 0' TERM INT

emit

sock=$(socket2)
if [ -z "$sock" ] || ! command -v socat >/dev/null 2>&1; then
  # No event stream: a plain 1s tick still keeps the clock correct.
  while :; do sleep 1; emit; done
fi

# One long-lived socat feeds this loop on fd 3. A `read -t 1` timeout is not
# an error here -- it is the 1s clock tick -- so the loop must NOT treat it as
# the stream ending, or every idle second would leak a new socat process.
# Process substitution keeps `last` in this shell (a pipe would subshell it).
while :; do
  exec 3< <(socat -u UNIX-CONNECT:"$sock" - 2>/dev/null)
  socat_ok=1
  while [ "$socat_ok" = 1 ]; do
    IFS= read -r -t 1 -u 3 line; rc=$?
    if [ "$rc" -eq 0 ]; then
      case "${line,,}" in
        *activespecial*|*focusedmon*|*monitoradded*) emit ;;
      esac
    else
      # rc >128 means the read timed out -- that is our 1s tick, not an error.
      # Anything else is EOF: the socket died, so reconnect.
      [ "$rc" -gt 128 ] || socat_ok=0
      emit
    fi
  done
  exec 3<&-
  sleep 0.5
  sock=$(socket2)
  [ -n "$sock" ] || { emit; sleep 1; }
done
