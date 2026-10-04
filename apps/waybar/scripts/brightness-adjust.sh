#!/usr/bin/env bash
# Scroll handler for the brightness module. Delegates to the unified
# hardware + software brightness scale.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/cli domain/brightness ui/waybar

cmd_up()   { brightness::up;   waybar::refresh brightness; }
cmd_down() { brightness::down; waybar::refresh brightness; }

declare -A COMMANDS=(
  [up]="cmd_up|raise brightness"
  [down]="cmd_down|lower brightness"
)

cli::dispatch "${1:-}" "${@:2}"
