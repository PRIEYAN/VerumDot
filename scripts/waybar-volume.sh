#!/usr/bin/env bash
# Volume module for waybar.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use ui/waybar domain/audio

readonly ICON_ON=$''
readonly ICON_MUTED=$''

if ! audio::available; then
  waybar::unavailable $'' "no audio backend (install pamixer or wireplumber)"
  exit 0
fi

volume=$(audio::volume) || {
  waybar::unavailable $'' "the audio sink is not reporting a volume"
  exit 0
}

if audio::muted; then
  waybar::emit_pct "${ICON_MUTED} ${volume}%" \
    'Click to unmute · scroll to change volume' "$volume" muted
else
  waybar::emit_pct "${ICON_ON} ${volume}%" \
    'Click to toggle mute · scroll to change volume' "$volume"
fi
