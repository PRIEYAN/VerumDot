#!/usr/bin/env bash
# Month navigation for the eww calendar panel.
#
#   eww-cal.sh prev | next | reset
#
# Bound to the panel's arrow buttons and to the Left/Right keys of the
# `calendar` submap in hypr.conf.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/cli os/state ui/eww core/paths

readonly OFFSET_KEY=calendar-offset
readonly DATA="${HYPR_SCRIPTS}/eww/cal-data.sh"

offset() { state::get "$OFFSET_KEY" 0 state::is_integer; }

apply() {
  local value=$1
  state::set "$OFFSET_KEY" "$value"
  eww::update "cal_offset=${value}" "cal_data=$("$DATA" "$value")"
}

cmd_prev()  { apply $(( $(offset) - 1 )); }
cmd_next()  { apply $(( $(offset) + 1 )); }
cmd_reset() { apply 0; }

declare -A COMMANDS=(
  [prev]="cmd_prev|show the previous month"
  [next]="cmd_next|show the next month"
  [reset]="cmd_reset|return to the current month"
)

cli::dispatch "${1:-reset}" "${@:2}"
