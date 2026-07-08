#!/usr/bin/env bash
# Brightness module for eww. Emits JSON {text, tooltip} with a sun glyph and
# the current percentage, computed from brightnessctl's raw/max values.

cur=$(brightnessctl get 2>/dev/null)
max=$(brightnessctl max 2>/dev/null)
if [ -z "$max" ] || [ "$max" -eq 0 ] 2>/dev/null; then
  printf '{"text":" --","tooltip":"Brightness unavailable"}\n'
  exit 0
fi

pct=$(( cur * 100 / max ))

# glyph ramps with level (UTF-8 byte escapes, PUA-safe)
#   brightness-7 U+F00E0 (high) / brightness-5 U+F00DE (med) / brightness-4 U+F00DD (low)
if   [ "$pct" -ge 66 ]; then icon=$(printf '\xf3\xb0\x83\xa0')
elif [ "$pct" -ge 33 ]; then icon=$(printf '\xf3\xb0\x83\x9e')
else                         icon=$(printf '\xf3\xb0\x83\x9d')
fi

printf '{"text":"%s %d%%","tooltip":"Brightness: %d%%  (scroll to adjust)"}\n' "$icon" "$pct" "$pct"
