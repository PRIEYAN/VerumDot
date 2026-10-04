#!/usr/bin/env bash
# Open the hidden special workspace, but only when swiping up from
# workspace 1. Bound to the 4-finger swipe-up gesture.
#
# jq rather than python throughout: jq is already a dependency and starts in
# about 5ms, which matters on a gesture binding.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use os/hypr

readonly SPECIAL=hidden

# Already open: nothing to do, and re-toggling would close it.
[[ $(hypr::active_special) == "special:${SPECIAL}" ]] && exit 0
[[ $(hypr::active_workspace) == 1 ]] || exit 0

hypr::toggle_special "$SPECIAL"
