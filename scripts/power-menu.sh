#!/usr/bin/env bash
#
# Power menu — rofi only, no eww.
#
# Two modes:
#   (no args)  emit the waybar module JSON for the power button
#   menu       open the picker
#
# The button glyphs are Nerd Font private-use codepoints. They are built
# here with $'\uXXXX' escapes rather than pasted in literally: PUA glyphs do
# not survive every editor/pipeline round-trip, and a silently emptied
# pattern in a `case` turns into `**)`, which matches ANY string and fires
# the first branch — i.e. an accidental shutdown. Codepoints cannot degrade
# that way.


# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
THEME="${HYPR_DIR}/apps/rofi/power.rasi"
HYPRLOCK_CONF="${HYPR_DIR}/apps/hyprlock/hyprlock.conf"
SHUTDOWN_SPLASH="${HYPR_DIR}/scripts/mogger_shutdown.sh"

if [ "$1" != "menu" ]; then
  printf '{"text":"%s","tooltip":"Power"}\n' $'\uF011'
  exit 0
fi

# These two arrays are parallel; index i describes one button.
GLYPHS=(
  $'\uF011'      # nf-fa-power_off
  $'\uEAD2'      # nf-cod-debug_restart
  $'\uF08B'      # nf-fa-sign_out
  $'\uF023'      # nf-fa-lock
)
ACTIONS=( shutdown reboot logout lock )

# Rows are the bare glyphs, deliberately unwrapped by Pango markup: an
# inline <span color> beats the theme's text-color, which would pin the
# icons to a fixed colour and make the black-on-white selected state
# impossible. Colour lives entirely in power.rasi.
sel=$(printf '%s\n' "${GLYPHS[@]}" \
  | rofi -dmenu -p "Power" -format i -theme "$THEME")

# Empty on Escape / dismissal.
[ -z "$sel" ] && exit 0

# rofi 2.x is new enough that `-format i` returning a bare index is not
# guaranteed. Integer => use it as the index; otherwise rofi handed back the
# row text, so recover the action by locating its glyph.
action=""
if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -lt "${#ACTIONS[@]}" ]; then
  action="${ACTIONS[$sel]}"
else
  for i in "${!GLYPHS[@]}"; do
    if [[ "$sel" == *"${GLYPHS[$i]}"* ]]; then
      action="${ACTIONS[$i]}"
      break
    fi
  done
fi

# An unrecognised selection exits rather than falling through to a default:
# every branch below is destructive, so guessing is worse than doing nothing.
[ -z "$action" ] && exit 0

case "$action" in
  shutdown) exec "$SHUTDOWN_SPLASH" ;;
  reboot)   exec systemctl reboot ;;
  logout)   exec hyprctl dispatch exit ;;
  lock)     exec hyprlock -c "$HYPRLOCK_CONF" ;;
esac
