#!/usr/bin/env bash
# Clock module for waybar, with a red "hidden-ws" class while the focused
# monitor is showing the special:hidden workspace.
#
# Ticks once a second and also reacts to compositor events, emitting only
# when the rendered output actually changes — waybar re-lays-out the bar on
# every line it receives, so an unchanged repaint is wasted work.
#
# The tooltip is deliberately minute-precision. It used to carry seconds,
# which made every one-second render differ from the last and so defeated
# the de-duplication entirely: the module emitted sixty times a minute and
# the bar relaid out on each. Seconds in a hover tooltip are not worth that.
#
# The event-stream plumbing (one long-lived socat, a 1s read timeout that is
# the tick rather than an error) lives in lib/os/hypr.sh.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use ui/waybar os/hypr

readonly HIDDEN_WORKSPACE=hidden

last=''

render() {
  local class=''
  hypr::special_workspace_open "$HIDDEN_WORKSPACE" && class='hidden-ws'
  waybar::emit "$(date '+%a %d %b  %H:%M')" "$(date '+%A, %d %B %Y  ·  %H:%M')" "$class"
}

emit() {
  local current; current=$(render)
  [[ $current == "$last" ]] && return 0
  printf '%s\n' "$current"
  last=$current
}

trap 'exit 0' TERM INT

emit
hypr::on_event '*activespecial*|*focusedmon*|*monitoradded*' emit
