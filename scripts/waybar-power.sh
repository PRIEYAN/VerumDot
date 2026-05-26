#!/usr/bin/env bash

if [ "$1" = "menu" ]; then
  # Toggle: if already open, close it
  if pgrep -f "power-center.py" >/dev/null; then
    pkill -f "power-center.py"
    exit 0
  fi
  setsid -f python3 /home/prieyan/.config/hypr/scripts/power-center.py >/dev/null 2>&1
  exit 0
fi

printf '{"text":"⏻","tooltip":"Power"}\n'
