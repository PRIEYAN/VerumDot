#!/usr/bin/env bash
# Screenshot module for waybar: a button that captures a selected region.
# The capture itself is scripts/screenshot.sh, so the keybind and the bar
# button cannot drift apart.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/cli core/paths ui/waybar

cmd_status() { waybar::emit $'\U000F0381' 'Click to select an area and screenshot'; }
cmd_take()   { exec "$(paths::script screenshot.sh)" selection; }

declare -A COMMANDS=(
  [status]="cmd_status|emit the waybar module JSON (the default)"
  [take]="cmd_take|capture a selected region"
)

cli::dispatch "${1:-status}" "${@:2}"
