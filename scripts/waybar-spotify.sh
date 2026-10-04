#!/usr/bin/env bash
# Now-playing module for waybar.
#
#   (no args)  emit the waybar module JSON
#   menu       toggle the quickshell media card
#   toggle     play/pause without opening anything

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/cli ui/waybar ui/quickshell ui/notify domain/player

readonly ICON_PLAYING=$''
readonly ICON_PAUSED=$''

cmd_status() {
  local status title artist icon
  if ! player::available; then
    waybar::emit '' 'playerctl is not installed'
    return 0
  fi

  if ! player::active; then
    waybar::emit '' 'Spotify: not playing'
    return 0
  fi

  status=$(player::status)
  title=$(player::title)
  artist=$(player::artist)
  [[ $status == Paused ]] && icon=$ICON_PAUSED || icon=$ICON_PLAYING

  waybar::emit "${icon}  ${title} — ${artist}" \
    "${status}: ${title} — ${artist}" \
    "${status,,}"
}

cmd_menu() {
  # The card is a quickshell daemon, so a click is an IPC toggle against the
  # already-running surface.
  quickshell::toggle spotify spotify && return 0
  notify::warn 'Media card unavailable' 'quickshell is not running.'
  return 1
}

cmd_toggle() { player::play_pause; }

declare -A COMMANDS=(
  [status]="cmd_status|emit the waybar module JSON (the default)"
  [menu]="cmd_menu|toggle the quickshell media card"
  [toggle]="cmd_toggle|play/pause the current track"
)

cli::dispatch "${1:-status}" "${@:2}"
