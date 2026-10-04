#!/usr/bin/env bash
# Close the hidden special workspace if it is open. Bound to the 4-finger
# swipe-down gesture; always allowed, since you can only be here after
# opening it from workspace 1.
#
# The 3-finger horizontal swipe has no notion of "the hidden workspace is
# open" and can silently change the regular workspace underneath while the
# overlay stays on screen. Forcing workspace 1 on close means you always
# land back where you started, regardless of what happened beneath.

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
readonly RETURN_TO=1

[[ $(hypr::active_special) == "special:${SPECIAL}" ]] || exit 0

hypr::toggle_special "$SPECIAL"
hypr::goto_workspace "$RETURN_TO"
