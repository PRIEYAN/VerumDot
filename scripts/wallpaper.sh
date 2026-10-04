#!/usr/bin/env bash
# Wallpaper setter. The desktop and the lock screen are separate choices;
# see lib/domain/wallpaper.sh for the tracking rule between them.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/cli core/migrate domain/wallpaper

migrate::run

cmd_init() { wallpaper::init; }

cmd_set() {
  cli::need 1 "set <path/to/image>" "$@"
  wallpaper::set "$1"
}

cmd_set_lock() {
  cli::need 1 "set-lock <path/to/image>" "$@"
  wallpaper::set_lock "$1"
}

cmd_get()  { wallpaper::current; echo; }
cmd_list() { wallpaper::list; }

declare -A COMMANDS=(
  [init]="cmd_init|start hyprpaper and restore both wallpapers (session start)"
  [set]="cmd_set|<image>  set the desktop wallpaper"
  [set-lock]="cmd_set_lock|<image>  pin the lock screen wallpaper"
  [get]="cmd_get|print the current desktop wallpaper"
  [list]="cmd_list|list available wallpapers"
)

cli::dispatch "${1:-get}" "${@:2}"
