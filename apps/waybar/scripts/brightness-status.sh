#!/usr/bin/env bash
# Brightness module for waybar.
#
# Shows the hardware percentage normally, or the boost factor while the
# software shader is active. The eye-comfort class tints the glyph amber.
#
# Both readings come from lib/domain/brightness.sh, which is also what
# applies them — previously this module re-derived "is a boost active?" with
# its own regex against the state file, so the bar and the control could
# disagree.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use ui/waybar domain/brightness domain/eyecomfort

readonly ICON=$''
readonly ICON_BOOSTED='⚡'

eye_class=''
eyecomfort::active && eye_class='eye-comfort'

if ! brightness::available; then
  waybar::unavailable "$ICON" 'install brightnessctl for real brightness control'
  exit 0
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
