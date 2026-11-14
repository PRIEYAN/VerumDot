#!/usr/bin/env bash
# Focus a workspace — for the waybar workspace buttons. Goes through os/hypr
# so the click works under both the Lua and the hyprlang config engines.
#
#   goto-workspace.sh <n>

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/log os/hypr

[[ ${1:-} =~ ^[0-9]+$ ]] || log::die "usage: goto-workspace.sh <workspace number>"
hypr::goto_workspace "$1"
