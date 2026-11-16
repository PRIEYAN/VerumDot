#!/usr/bin/env bash
# Brightness module for waybar.
#
#   brightness-status.sh           print one module object
#   brightness-status.sh --watch   print one object now, then one per change
#
# Shows the hardware percentage normally, or the boost factor while the
# software shader is active. The eye-comfort class tints the glyph amber.
#
# Both readings come from lib/domain/brightness.sh, which is also what
# applies them — previously this module re-derived "is a boost active?" with
# its own regex against the state file, so the bar and the control could
# disagree.
#
# --watch reacts to two event sources:
#   - the kernel backlight (udev), which fires for every brightnessctl write,
#     whichever process made it: the keys, the scroll handler, the control
#     centre slider;
#   - the state directory, which holds the boost factor and the eye-comfort
#     flag. Those change the bar without touching the backlight.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use ui/waybar domain/brightness domain/eyecomfort

readonly ICON=$'\uf185'  # nf-fa-sun_o
readonly ICON_BOOSTED='⚡'

# emit_brightness — one module object for the current brightness state.
emit_brightness() {
  local eye_class='' boost percent tooltip
  eyecomfort::active && eye_class='eye-comfort'

  if ! brightness::available; then
    waybar::unavailable "$ICON" 'install brightnessctl for real brightness control'
    return 0
  fi

  if brightness::boosted; then
    boost=$(brightness::boost_percent)
    waybar::emit_pct "${ICON_BOOSTED} ${boost}%" \
      "Software boost active · ${boost}%" "$boost" boosted "$eye_class"
  else
    percent=$(brightness::hardware_percent)
    tooltip='Scroll to adjust brightness'
    [[ -n $eye_class ]] && tooltip+=' · eye comfort on'
    waybar::emit_pct "${ICON} ${percent}%" "$tooltip" "$percent" "$eye_class"
  fi
}

if [[ ${1:-} == --watch ]]; then
  # The state directory has to exist before inotifywait can watch it.
  mkdir -p -- "$HYPR_STATE_DIR"
  # stdbuf: udevadm and inotifywait block-buffer when writing to a pipe.
  waybar::watch emit_brightness "
    { stdbuf -oL udevadm monitor --udev --subsystem-match=backlight 2>/dev/null \
        | grep --line-buffered ' change ' &
      stdbuf -oL inotifywait -q -m -e close_write,moved_to,delete,create \
        --format x '${HYPR_STATE_DIR}' 2>/dev/null &
      wait; }"
  exit 0
fi

emit_brightness
