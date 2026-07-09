#!/usr/bin/env bash
# Adjust screen brightness via brightnessctl and push the new % straight into
# eww in a SINGLE update — no separate status-script/jq round-trip — so rapid
# scrolling stays smooth. Usage: brightness-adjust.sh up|down

case "$1" in
  up)   brightnessctl set +5% -q ;;
  down) brightnessctl set 5%- -q ;;
esac

# brightnessctl -m prints: device,class,current,percent,max  (percent has a %)
pct=$(brightnessctl -m 2>/dev/null | awk -F, '{gsub("%","",$4); print $4}')

# glyph ramps with level (UTF-8 byte escapes, PUA-safe)
if   [ "${pct:-0}" -ge 66 ]; then icon=$(printf '\xf3\xb0\x83\xa0')
elif [ "${pct:-0}" -ge 33 ]; then icon=$(printf '\xf3\xb0\x83\x9e')
else                              icon=$(printf '\xf3\xb0\x83\x9d')
fi

eww update "brightness_text=${icon} ${pct}%" \
           "brightness_tooltip=Brightness: ${pct}%  (scroll to adjust)" \
  >/dev/null 2>&1
