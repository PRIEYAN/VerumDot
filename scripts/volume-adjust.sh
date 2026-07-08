#!/usr/bin/env bash
# Adjust output volume by 5% via pamixer. Usage: volume-adjust.sh up|down
# Kept as a script (rather than inline eww :onscroll) so quoting/`{}`
# substitution quirks can't swallow the command.

case "$1" in
  up)   pamixer -i 5 ;;
  down) pamixer -d 5 ;;
esac
