#!/usr/bin/env bash
# CPU power-mode module and its toggle. Bound to SUPER+P.
#
# The glyph colour is carried by the battery module's class, not this one;
# see lib/domain/power.sh for why ppd is the source of truth and the cached
# value only exists so the bar can paint without a D-Bus round trip.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/cli core/guard core/migrate os/state ui/waybar domain/power

migrate::run

cmd_status() {
  local mode; mode=$(power::mode)
  waybar::emit "${POWER_GLYPH[$mode]} ${mode}" \
    'Click to cycle the CPU power mode' "mode-${mode}"
}

cmd_toggle() { power::cycle; }

cmd_set() {
  cli::need 1 "set <normal|performance|battery>" "$@"
  power::set_mode "$1" || log::usage "set <normal|performance|battery>"
}

# cache — record a mode that something else has *already* applied, and
# repaint the bar. The control centre drives PowerProfiles directly, so
# calling `set` from there would re-apply the profile and loop back through
# its own onProfileChanged handler.
cmd_cache() {
  cli::need 1 "cache <normal|performance|battery>" "$@"
  guard::one_of "$1" "${POWER_MODES[@]}" >/dev/null || log::usage "cache <normal|performance|battery>"
  state::set "$POWER_STATE_KEY" "$1"
  waybar::refresh battery
}

declare -A COMMANDS=(
  [status]="cmd_status|emit the waybar module JSON (the default)"
  [toggle]="cmd_toggle|cycle normal -> performance -> battery"
  [set]="cmd_set|<normal|performance|battery>  set the mode directly"
  [cache]="cmd_cache|<mode>  record an externally-applied mode and repaint"
)

cli::dispatch "${1:-status}" "${@:2}"
