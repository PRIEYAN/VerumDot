#!/usr/bin/env bash
# Microphone module for eww. Shows a mic glyph, or a muted/disabled mic glyph
# when the default source is muted. wpctl reports "[MUTED]" when muted.

info=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null)

if [ -z "$info" ]; then
  printf '{"text":"","tooltip":"No microphone","class":"inactive"}\n'
  exit 0
fi

if printf '%s' "$info" | grep -q MUTED; then
  # muted / disabled mic
  printf '{"text":"","tooltip":"Microphone muted — click to enable","class":"inactive"}\n'
else
  # live mic
  printf '{"text":"","tooltip":"Microphone on — click to mute","class":"active"}\n'
fi
