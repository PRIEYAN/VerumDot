#!/usr/bin/env bash
# Idle management: lock after 5 minutes, blank the screen after 10.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/guard

guard::require hypridle
exec hypridle --lock "${HYPR_IDLE_LOCK:-5m}" --off "${HYPR_IDLE_OFF:-10m}"
