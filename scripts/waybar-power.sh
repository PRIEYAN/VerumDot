#!/usr/bin/env bash

if [ "$1" = "menu" ]; then
  eww -c /home/prieyan/.config/hypr/apps/eww open --toggle power
  exit 0
fi

printf '{"text":"⏻","tooltip":"Power"}\n'
