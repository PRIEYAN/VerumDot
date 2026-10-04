#!/usr/bin/env bash
# Compact media popup (rofi).
#
# Superseded for day-to-day use by the quickshell card, which can redraw in
# place; kept as the fallback for a session without quickshell. Layout is
# [ art | title / artist / progress / times + prev · play-pause · next ].

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use ui/rofi ui/markup ui/theme domain/player

readonly THEME=spotify
readonly ICON_PREVIOUS='󰒮'
readonly ICON_PLAY='󰐊'
readonly ICON_PAUSE='󰏤'
readonly ICON_NEXT='󰒭'

readonly ACTION_PREVIOUS=0
readonly ACTION_PLAY_PAUSE=1
readonly ACTION_NEXT=2

rofi::available   || log::die 'rofi is not installed'
player::available || log::die 'playerctl is not installed'
rofi::toggle spotify || exit 0

if ! player::active; then
  printf 'Close\n' | rofi -dmenu -mesg 'Nothing playing' \
    -theme "$(rofi::theme_path "$THEME")" -no-custom \
    -theme-str 'mainbox { children: [ body ]; } icon { enabled: false; }' >/dev/null
  exit 0
fi

position=$(player::position)
length=$(player::length)
remaining=$(( length - position ))
(( remaining < 0 )) && remaining=0

# Title and artist are arbitrary text from the player, so they are escaped
# before being interpolated into markup — an ampersand in a track name used
# to break the whole row.
info=$(printf '%s\n%s\n%s\n%s' \
  "$(markup::bold "$(markup::escape "$(player::title)")")" \
  "$(markup::span "$(markup::escape "$(player::artist)")" "$THEME_DIM")" \
  "$(markup::track "$(player::progress_percent)")" \
  "$(markup::span "$(printf '%s&#9;&#9;&#9;&#9;-%s' \
      "$(markup::duration "$position")" "$(markup::duration "$remaining")")" "$THEME_DIM")")

player::playing && toggle_icon=$ICON_PAUSE || toggle_icon=$ICON_PLAY

choice=$(printf '%s\n' "$ICON_PREVIOUS" "$toggle_icon" "$ICON_NEXT" \
  | rofi -dmenu -markup-rows -mesg "$info" \
      -theme "$(rofi::theme_path "$THEME")" \
      -theme-str "icon { filename: \"$(player::art)\"; }" \
      -selected-row "$ACTION_PLAY_PAUSE" -format i -no-custom -p '') || exit 0

# Act and close. Re-rendering in place here made rofi exit and relaunch,
# which is the visible close-then-reopen flicker the quickshell card fixed.
case $choice in
  "$ACTION_PREVIOUS")   player::previous ;;
  "$ACTION_PLAY_PAUSE") player::play_pause ;;
  "$ACTION_NEXT")       player::next ;;
esac
