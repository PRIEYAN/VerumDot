#!/usr/bin/env bash
# Wallpaper picker: a rofi grid of thumbnails.
#
#   (no args)  set the desktop wallpaper
#   lock       set the lock screen wallpaper instead

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/cli ui/rofi domain/wallpaper

readonly THEME=wallpaper

pick() {
  local prompt=$1 path selection
  [[ -d $HYPR_WALLPAPER_DIR ]] || log::die -c 0 "no wallpaper directory at ${HYPR_WALLPAPER_DIR}"
  rofi::available || log::die 'rofi is not installed'

  # wallpaper.rasi renders a grid of large previews with the filenames
  # hidden. The row still carries the basename as its value, which is what
  # the selection resolves back to.
  selection=$(
    while IFS= read -r path; do
      rofi::icon_row "$(basename -- "$path")" "$path"
    done < <(wallpaper::list) \
      | rofi::menu "$THEME" "$prompt" -show-icons
  )
  [[ -z $selection ]] && return 1
  printf '%s/%s' "$HYPR_WALLPAPER_DIR" "$selection"
}

cmd_desktop() {
  local choice; choice=$(pick 'Wallpaper') || return 0
  # Detached: setting a wallpaper starts a watcher that outlives the picker.
  proc::detach "$(paths::script wallpaper.sh)" set "$choice"
}

cmd_lock() {
  local choice; choice=$(pick 'Lock Screen Wallpaper') || return 0
  proc::detach "$(paths::script wallpaper.sh)" set-lock "$choice"
}

declare -A COMMANDS=(
  [desktop]="cmd_desktop|pick the desktop wallpaper (the default)"
  [lock]="cmd_lock|pick the lock screen wallpaper"
)

cli::dispatch "${1:-desktop}" "${@:2}"
