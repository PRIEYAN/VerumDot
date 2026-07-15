#!/usr/bin/env bash
#
# Tiny helper: close an eww window. Pure shell.
#   eww-close.sh <window>

eww -c /home/prieyan/.config/hypr/apps/eww close "$1" >/dev/null 2>&1
