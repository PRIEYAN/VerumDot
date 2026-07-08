#!/usr/bin/env bash
# Adjust screen brightness via brightnessctl. Usage: brightness-adjust.sh up|down
# Steps by 5%, clamped by brightnessctl itself (won't go below 1%).

case "$1" in
  up)   brightnessctl set +5% -q ;;
  down) brightnessctl set 5%- -q ;;
esac
