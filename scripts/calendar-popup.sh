#!/usr/bin/env bash
# Rofi calendar dropdown under the waybar clock.
#
#   Left/Right  change month      Up/Down  change year
#   Return      jump to today     Esc      close
#
# Clicking the clock again while it is open dismisses it.
#
# The grid itself is built by lib/ui/calendar.sh; this file is the rofi
# key-binding layer over it.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use ui/rofi ui/calendar

readonly THEME=calendar

# rofi's custom-key exit codes, named. The mapping between a -kb-custom-N
# flag and the code it returns (10 + N - 1) is the kind of off-by-one that
# is invisible as a bare integer in a case block.
readonly KEY_PREV_MONTH=10
readonly KEY_NEXT_MONTH=11
readonly KEY_PREV_YEAR=12
readonly KEY_NEXT_YEAR=13
readonly KEY_TODAY=14

rofi::available || log::die 'rofi is not installed'
rofi::toggle calendar || exit 0

year=$(date +%Y)
month=$(date +%-m)

while :; do
  grid=$(calendar::grid "$year" "$month")
  selected=$(calendar::selected_row "$year" "$month")

  # The defaults that own Left/Right/Up/Down/Return are moved aside before
  # those keys are rebound, or rofi's own cursor movement wins.
  printf '%s\n' "$grid" | rofi \
    -dmenu -markup-rows \
    -theme "$(rofi::theme_path "$THEME")" \
    -p "$(calendar::title "$year" "$month")" \
    -u '0,1,2,3,4,5,6' \
    -selected-row "$selected" \
    -no-custom \
    -kb-move-char-back 'Control+b' \
    -kb-move-char-forward 'Control+f' \
    -kb-row-up 'Control+p' \
    -kb-row-down 'Control+n' \
    -kb-accept-entry '' \
    -kb-custom-1 'Left,h' \
    -kb-custom-2 'Right,l' \
    -kb-custom-3 'Up,k' \
    -kb-custom-4 'Down,j' \
    -kb-custom-5 'Return,KP_Enter' \
    >/dev/null
  code=$?

  case $code in
    "$KEY_PREV_MONTH") read -r year month < <(calendar::normalize "$year" $(( month - 1 ))) ;;
    "$KEY_NEXT_MONTH") read -r year month < <(calendar::normalize "$year" $(( month + 1 ))) ;;
    "$KEY_PREV_YEAR")  year=$(( year - 1 )) ;;
    "$KEY_NEXT_YEAR")  year=$(( year + 1 )) ;;
    "$KEY_TODAY")      year=$(date +%Y); month=$(date +%-m) ;;
    *) exit 0 ;;
  esac
done
