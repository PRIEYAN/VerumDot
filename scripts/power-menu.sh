#!/usr/bin/env bash
# Power menu.
#
#   (no args)  emit the waybar module JSON for the power button
#   menu       open the picker
#
# The glyphs are Nerd Font private-use codepoints, built with $'\uXXXX'
# escapes rather than pasted in literally. PUA glyphs do not survive every
# editor and pipeline round-trip, and a silently emptied pattern in a `case`
# becomes `**)`, which matches anything and fires the first branch — an
# accidental shutdown. Codepoints cannot degrade that way.
#
# Dispatch is by action, never by glyph, and an unresolved selection exits
# rather than falling through: every branch here is irreversible, so
# guessing is strictly worse than doing nothing.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/cli ui/rofi ui/waybar domain/power

# Parallel arrays: index i is one button.
readonly -a GLYPHS=( $'' $'' $'' $'' )
readonly -a ACTIONS=( shutdown reboot logout lock )

cmd_status() { waybar::emit $'' "Control Centre"; }

cmd_menu() {
  rofi::available || log::die "rofi is not installed"

  local selection index
  # Rows are bare glyphs, deliberately without inline Pango colour: a
  # <span color> would beat the theme's text-color and make the inverted
  # black-on-white selected state impossible. Colour lives in power.rasi.
  selection=$(printf '%s\n' "${GLYPHS[@]}" | rofi::menu_index power "Power")
  [[ -z $selection ]] && exit 0

  index=$(rofi::resolve_index "$selection" "${GLYPHS[@]}") || exit 0

  case "${ACTIONS[$index]}" in
    shutdown) power::shutdown ;;
    reboot)   power::reboot ;;
    logout)   power::logout ;;
    lock)     power::lock ;;
  esac
}

declare -A COMMANDS=(
  [status]="cmd_status|emit the waybar module JSON (the default)"
  [menu]="cmd_menu|open the power picker"
)

cli::dispatch "${1:-status}" "${@:2}"
