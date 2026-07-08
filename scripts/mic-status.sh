#!/usr/bin/env bash
# Microphone module for eww. Shows a mic glyph, or a muted/disabled mic glyph
# when the default source is muted. wpctl reports "[MUTED]" when muted.

# Glyphs via UTF-8 byte escapes (PUA-safe).
#   microphone      U+F036C (live)
#   microphone-off  U+F036D (muted)
G_MIC=$(printf '\xf3\xb0\x8d\xac')
G_MIC_OFF=$(printf '\xf3\xb0\x8d\xad')

info=$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null)

if [ -z "$info" ]; then
  printf '{"text":"%s","tooltip":"No microphone","class":"inactive"}\n' "$G_MIC_OFF"
  exit 0
fi

if printf '%s' "$info" | grep -q MUTED; then
  printf '{"text":"%s","tooltip":"Microphone muted — click to enable","class":"inactive"}\n' "$G_MIC_OFF"
else
  printf '{"text":"%s","tooltip":"Microphone on — click to mute","class":"active"}\n' "$G_MIC"
fi
