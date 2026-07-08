#!/usr/bin/env bash

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

if [ "$1" = "menu" ]; then
  setsid -f /home/prieyan/.config/hypr/scripts/spotify-center.py >/tmp/spotify-center.log 2>&1
  exit 0
fi

if [ "$1" = "toggle" ]; then
  playerctl -p spotify play-pause >/dev/null 2>&1
  exit 0
fi

status=$(playerctl -p spotify status 2>/dev/null)
if [ -z "$status" ] || [ "$status" = "Stopped" ]; then
  printf '{"text":"","tooltip":"Spotify: not playing"}\n'
  exit 0
fi

title=$(playerctl -p spotify metadata xesam:title 2>/dev/null)
artist=$(playerctl -p spotify metadata xesam:artist 2>/dev/null)
[ -z "$title" ] && title="Unknown"
[ -z "$artist" ] && artist="Unknown"

icon=""
[ "$status" = "Paused" ] && icon=""

label="$title — $artist"
label_json=$(json_escape "$label")
tip_json=$(json_escape "$status: $title — $artist")
printf '{"text":"%s  %s","tooltip":"%s","class":"%s"}\n' "$icon" "$label_json" "$tip_json" "$(printf '%s' "$status" | tr '[:upper:]' '[:lower:]')"
