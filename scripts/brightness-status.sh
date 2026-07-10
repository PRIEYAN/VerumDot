#!/usr/bin/env bash
# Brightness module for eww. Reports the same unified 10..150 level as
# brightness-adjust.sh: hardware % up to 100, plus the boost shader
# multiplier (1.0..1.5x -> 100..150) when engaged.

# self-locate so sibling scripts resolve for any user / checkout location
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOST="$DIR/brightness_boost.sh"

cur=$(brightnessctl get 2>/dev/null)
max=$(brightnessctl max 2>/dev/null)
if [ -z "$max" ] || [ "$max" -eq 0 ] 2>/dev/null; then
  printf '{"text":" --","tooltip":"Brightness unavailable"}\n'
  exit 0
fi

hw=$(( cur * 100 / max ))
mult=$(bash "$BOOST" get 2>/dev/null); mult=${mult:-1.0}
boost_active=$(awk "BEGIN{print ($mult > 1.0) ? 1 : 0}")

if [ "$boost_active" -eq 1 ]; then
  level=$(awk "BEGIN{printf \"%d\", 100 + ($mult - 1.0) * 100 + 0.5}")
else
  level=$hw
fi

# glyph ramps with level (UTF-8 byte escapes, PUA-safe)
#   brightness-7 U+F00E0 (high) / brightness-5 U+F00DE (med) / brightness-4 U+F00DD (low)
if   [ "$level" -ge 66 ]; then icon=$(printf '\xf3\xb0\x83\xa0')
elif [ "$level" -ge 33 ]; then icon=$(printf '\xf3\xb0\x83\x9e')
else                           icon=$(printf '\xf3\xb0\x83\x9d')
fi

tip="Brightness: ${level}%"
[ "$level" -gt 100 ] && tip="$tip (boost)"
printf '{"text":"%s %d%%","tooltip":"%s  (scroll to adjust)"}\n' "$icon" "$level" "$tip"
