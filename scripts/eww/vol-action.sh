#!/usr/bin/env bash
# Volume actions for the eww panel.
#
#   vol-action.sh set <0-150>
#   vol-action.sh mute
#
# domain/audio repaints the correct waybar module itself. This script used
# to poke RTMIN+1 by hand after a volume change — that is the *brightness*
# module, so the bar's volume reading never actually refreshed.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/cli core/paths domain/audio ui/eww

readonly DATA="${HYPR_SCRIPTS}/eww/vol-data.sh"

sync_panel() { eww::update "vol_state=$("$DATA")"; }

cmd_set() {
  cli::need 1 "set <0-150>" "$@"
  [[ $1 =~ ^[0-9]+$ ]] || log::usage "set <0-150>"
  audio::set_volume "$1"
  sync_panel
}

cmd_mute() {
  audio::toggle_mute
  sync_panel
}

declare -A COMMANDS=(
  [set]="cmd_set|<0-150>  set the output volume"
  [mute]="cmd_mute|toggle mute"
)

cli::dispatch "${1:-}" "${@:2}"
