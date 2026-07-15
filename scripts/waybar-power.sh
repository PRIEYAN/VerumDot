#!/usr/bin/env bash

if [ "$1" = "menu" ]; then
  # Toggle: if already open, close it
  if pgrep -f "power-center.sh" >/dev/null; then
    pkill -f "power-center.sh"
    exit 0
  fi
  setsid -f /home/prieyan/.config/hypr/scripts/power-center.sh >/dev/null 2>&1
  exit 0
fi

printf '{"text":"⏻","tooltip":"Power"}\n'
