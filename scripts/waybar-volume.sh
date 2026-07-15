#!/usr/bin/env bash

if [ "$1" = "menu" ]; then
  eww -c /home/prieyan/.config/hypr/apps/eww open --toggle volume
  exit 0
fi

if volume=$(pamixer --get-volume 2>/dev/null); then
  if pamixer --get-mute 2>/dev/null | grep -Eq 'true|1'; then
    printf '{"text":"󰝟 %s%%","tooltip":"Muted - click for volume menu"}\n' "$volume"
  else
    printf '{"text":"󰕾 %s%%","tooltip":"Volume - click for menu, scroll to adjust"}\n' "$volume"
  fi
elif wpctl get-volume @DEFAULT_AUDIO_SINK@ >/dev/null 2>&1; then
  volume=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{printf "%d", $2 * 100}')
  if wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q MUTED; then
    printf '{"text":"󰝟 %s%%","tooltip":"Muted - click for volume menu"}\n' "$volume"
  else
    printf '{"text":"󰕾 %s%%","tooltip":"Volume - click for menu, scroll to adjust"}\n' "$volume"
  fi
else
  printf '{"text":"󰕾","tooltip":"Audio status unavailable"}\n'
fi
