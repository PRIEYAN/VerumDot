#!/usr/bin/env bash
# Turn the outputs' backlight on or off — for hypridle's listener, which
# cannot know whether Hyprland is running the Lua or the hyprlang config
# engine (they take different `hyprctl dispatch` syntax). os/hypr does.
#
#   dpms.sh on|off

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/log os/hypr

case "${1:-}" in
  on|off) hypr::dpms "$1" ;;
  *) log::die "usage: dpms.sh on|off" ;;
esac
