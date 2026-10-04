#!/usr/bin/env bash
# ui/rofi_script.sh — the other side of rofi: being run *by* it.
#
# ui/rofi.sh launches rofi. This module is for rofi script mode, where rofi
# re-executes the script on every keypress it is told to act on and reads
# NUL-prefixed directives from its stdout.
#
# Script mode exists here for one reason: rofi has no refresh timer and no
# IPC, so a -dmenu panel can only update by exiting and relaunching — a
# measured 58ms window teardown each time. In script mode rofi repaints the
# window it already has, so a refresh key updates the numbers in place with
# no flicker and no lost cursor position.
#
# The directives are an easy thing to get subtly wrong by hand (the
# separator is \x1f, not a colon, and a missing \0 turns a directive into a
# visible row), so they are named functions.

# rofi_script::prompt <text>     — the panel's prompt line
# rofi_script::markup_rows       — rows contain Pango markup
# rofi_script::no_custom         — refuse free text
# rofi_script::keep_selection    — keep the cursor where it was across a repaint
rofi_script::prompt()         { printf '\0prompt\x1f%s\n' "$1"; }
rofi_script::message()        { printf '\0message\x1f%s\n' "$1"; }
rofi_script::markup_rows()    { printf '\0markup-rows\x1ftrue\n'; }
rofi_script::no_custom()      { printf '\0no-custom\x1ftrue\n'; }
rofi_script::keep_selection() { printf '\0keep-selection\x1ftrue\n'; }

# rofi_script::is_first_paint — rofi sets ROFI_RETV=0 for the initial draw
# and 1 when a row is activated. Both just re-render here, which is what
# makes every activation key a live refresh.
rofi_script::is_first_paint() { [[ ${ROFI_RETV:-0} == 0 ]]; }

# rofi_script::header <prompt> — the directive block every repaint re-emits.
#
# Re-emitted rather than sent once because the prompt carries live data (the
# battery line), so it has to be refreshed along with the rows.
rofi_script::header() {
  rofi_script::prompt "$1"
  rofi_script::markup_rows
  rofi_script::no_custom
  rofi_script::keep_selection
}
