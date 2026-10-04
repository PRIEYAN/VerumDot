#!/usr/bin/env bash
# ui/eww.sh — the eww panels that remain.
#
# Most popups have moved to quickshell (which can redraw in place) or rofi
# (for plain list menus); the calendar and volume panels are what is left.
# This wrapper exists mainly because every caller built the command as
#     EWW="eww -c "${HYPR_EWW}""
# — nested double quotes, which collapse to an unquoted path. It worked only
# because the path happens to contain no spaces.

hypr::use core/guard core/paths os/proc

eww::available() { guard::has eww; }

eww::run()    { proc::quiet eww -c "$HYPR_EWW" "$@"; }
eww::open()   { eww::run open "$@"; }
eww::close()  { eww::run close "$@"; }
eww::toggle() { eww::run open --toggle "$1"; }

# eww::update <var>=<value>... — push values into the panel's state.
eww::update() { eww::run update "$@"; }
