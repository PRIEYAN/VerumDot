#!/usr/bin/env bash
# Microphone module for waybar.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use ui/waybar domain/audio

readonly ICON_LIVE=$''   # nf-fa-microphone
readonly ICON_MUTED=$''  # nf-fa-microphone_slash

if ! audio::available; then
  waybar::unavailable "$ICON_MUTED" "no audio backend (install pamixer or wireplumber)"
  exit 0
fi

if audio::mic_muted; then
  waybar::emit "$ICON_MUTED" 'Microphone muted — click to unmute' muted
else
  waybar::emit "$ICON_LIVE" 'Microphone live — click to mute'
fi
