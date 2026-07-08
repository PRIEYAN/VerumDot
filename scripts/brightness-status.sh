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

# glyph ramps with level
if   [ "$pct" -ge 66 ]; then icon=""
elif [ "$pct" -ge 33 ]; then icon=""
else                         icon=""
fi

printf '{"text":"%s %d%%","tooltip":"Brightness: %d%%  (scroll to adjust)"}\n' "$icon" "$pct" "$pct"
