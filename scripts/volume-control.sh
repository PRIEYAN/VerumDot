#!/usr/bin/env bash
# Volume keys. Bound to XF86AudioRaiseVolume / LowerVolume / Mute.
#
# hypr.conf used to carry the whole
#   wpctl ... || pamixer ... || pactl ...
# fallback chain inline, three times, with its own copy of the step size and
# the 150% boost limit — and a different copy of the same chain lived in
# scripts/eww/vol-action.sh. The chain is lib/domain/audio.sh now.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/cli domain/audio

cmd_up()   { audio::step_volume up; }
cmd_down() { audio::step_volume down; }
cmd_mute() { audio::toggle_mute; }
cmd_mic()  { audio::toggle_mic; }

cmd_set() {
  cli::need 1 "set <0-150>" "$@"
  [[ $1 =~ ^[0-9]+$ ]] || log::usage "set <0-150>"
  audio::set_volume "$1"
}

declare -A COMMANDS=(
  [up]="cmd_up|raise the output volume one step"
  [down]="cmd_down|lower the output volume one step"
  [mute]="cmd_mute|toggle output mute"
  [mic]="cmd_mic|toggle microphone mute"
  [set]="cmd_set|<0-150>  set the output volume"
)

cli::dispatch "${1:-}" "${@:2}"
