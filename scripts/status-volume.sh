#!/usr/bin/env bash

if [ "$1" = "menu" ]; then
  choice=$(printf '%s\n' "󰝟  Mute / Unmute" "󰖀  10%" "󰕾  25%" "󰕾  50%" "󰕾  75%" "󰕾  100%" | rofi -dmenu -p "Volume" -theme /home/prieyan/.config/hypr/apps/rofi/waybar-menu.rasi)
  case "$choice" in
    *Mute*) pamixer -t ;;
    *10%*) pamixer --set-volume 10 ;;
    *25%*) pamixer --set-volume 25 ;;
    *50%*) pamixer --set-volume 50 ;;
    *75%*) pamixer --set-volume 75 ;;
    *100%*) pamixer --set-volume 100 ;;
    *) exit 0 ;;
  esac
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
