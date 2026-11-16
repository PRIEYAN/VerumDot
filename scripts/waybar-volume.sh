#!/usr/bin/env bash
# Volume module for waybar.
#
#   waybar-volume.sh           print one module object
#   waybar-volume.sh --watch   print one object now, then one per sink change
#
# config.jsonc runs the --watch form as a continuous exec. pactl reports every
# change to the default sink whoever made it (the volume keys, the scroll
# handler, the control centre, wpctl), so the bar follows the real value
# without polling and without each writer having to remember to signal it.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use ui/waybar domain/audio

readonly ICON_ON=$'\U000f057e'     # 󰕾 nf-md-volume_high
readonly ICON_MUTED=$'\U000f075f'  # 󰝟 nf-md-volume_off

# emit_volume — one module object for the current state of the default sink.
emit_volume() {
  local volume
  if ! audio::available; then
    waybar::unavailable "$ICON_MUTED" "no audio backend (install pamixer or wireplumber)"
    return 0
  fi

  volume=$(audio::volume) || {
    waybar::unavailable "$ICON_MUTED" "the audio sink is not reporting a volume"
    return 0
  }

  if audio::muted; then
    waybar::emit_pct "${ICON_MUTED} ${volume}%" \
      'Click to unmute · scroll to change volume' "$volume" muted
  else
    waybar::emit_pct "${ICON_ON} ${volume}%" \
      'Click to toggle mute · scroll to change volume' "$volume"
  fi
}

if [[ ${1:-} == --watch ]]; then
  # stdbuf: pactl block-buffers when writing to a pipe, which would hold
  # events back until its buffer filled.
  waybar::watch emit_volume \
    'stdbuf -oL pactl subscribe 2>/dev/null | grep --line-buffered "on sink"'
  exit 0
fi

emit_volume
