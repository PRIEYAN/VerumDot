#!/usr/bin/env bash
#
# Tiny helper: set an eww variable. Keeps onclick strings in the .yuck
# short and free of nested quotes. Pure shell.
#   eww-set.sh <var> <value>

eww -c /home/prieyan/.config/hypr/apps/eww update "$1=$2" >/dev/null 2>&1
