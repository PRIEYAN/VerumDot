#!/usr/bin/env bash
# Toggle a quickshell surface over IPC, starting its daemon first if needed.
# Exits non-zero when quickshell is unavailable, so callers can fall back.
#
#   qs-toggle.sh <surface under apps/quickshell> <IpcHandler target>

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use ui/quickshell

surface=${1:?usage: qs-toggle.sh <surface> <ipc target>}
target=${2:?usage: qs-toggle.sh <surface> <ipc target>}

quickshell::toggle "$surface" "$target"
