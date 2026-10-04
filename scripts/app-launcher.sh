#!/usr/bin/env bash
# App launcher: the quickshell launcher, falling back to rofi's drun mode
# when quickshell is unavailable.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use ui/quickshell ui/rofi

quickshell::toggle launcher launcher && exit 0

rofi::available || log::die 'neither quickshell nor rofi is installed'
exec rofi -show drun -config "$ROFI_CONFIG"
