#!/usr/bin/env bash
# Screen brightness, up and down across the combined hardware/shader scale.
# Bound to XF86MonBrightnessUp / Down in hypr.conf.
#
# All of the policy lives in lib/domain/brightness.sh; this file is only the
# command-line face of it.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/cli core/migrate domain/brightness ui/waybar

migrate::run

cmd_up()    { brightness::up;    waybar::refresh brightness; }
cmd_down()  { brightness::down;  waybar::refresh brightness; }
cmd_reset() { brightness::reset; waybar::refresh brightness; }

cmd_set() {
  cli::need 1 "set <0-100>" "$@"
  brightness::set_percent "$1"
  waybar::refresh brightness
}

cmd_get() {
  printf 'hardware=%s%% boost=%sx effective=%s%%\n' \
    "$(brightness::hardware_percent)" "$(brightness::boost)" "$(brightness::boost_percent)"
}

declare -A COMMANDS=(
  [up]="cmd_up|raise brightness, boosting past hardware maximum"
  [down]="cmd_down|lower brightness, unwinding any boost first"
  [set]="cmd_set|<0-100>  set the hardware backlight directly"
  [reset]="cmd_reset|clear any software boost"
  [get]="cmd_get|report the current levels"
)

cli::dispatch "${1:-get}" "${@:2}"
