#!/usr/bin/env bash

now=$(date '+%A, %d %B %Y  %H:%M')
calendar=$(cal -3)

printf '%s\n' "$calendar" | rofi -dmenu -p "$now" -theme /home/prieyan/.config/hypr/apps/rofi/calendar.rasi
