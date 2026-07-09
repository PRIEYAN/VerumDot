#!/usr/bin/env bash
# Adjust output volume by 5% via pamixer, 0..150 (above 100 = boost/amplify),
# then push the new % into eww in a single update so scrolling stays smooth.
# Usage: volume-adjust.sh up|down

MAX=150
STEP=5

cur=$(pamixer --get-volume 2>/dev/null); cur=${cur:-0}

case "$1" in
  up)   new=$(( cur + STEP )); [ "$new" -gt "$MAX" ] && new=$MAX ;;
  down) new=$(( cur - STEP )); [ "$new" -lt 0 ] && new=0 ;;
  *)    new=$cur ;;
esac

# --allow-boost lets pamixer set above 100%.
pamixer --allow-boost --set-volume "$new" >/dev/null 2>&1

muted=$(pamixer --get-mute 2>/dev/null)
vol=$(pamixer --get-volume 2>/dev/null); vol=${vol:-$new}

if [ "$muted" = "true" ]; then
  icon=$(printf '\xf3\xb0\x9d\x9f')      # volume-mute   U+F075F
  cls="muted"
elif [ "$vol" -gt 100 ]; then
  icon=$(printf '\xf3\xb0\x95\xbe')      # volume-high   U+F057E  (boost range)
  cls="boost"
elif [ "$vol" -ge 66 ]; then
  icon=$(printf '\xf3\xb0\x95\xbe')      # volume-high   U+F057E
  cls=""
elif [ "$vol" -ge 33 ]; then
  icon=$(printf '\xf3\xb0\x96\x80')      # volume-medium U+F0580
  cls=""
else
  icon=$(printf '\xf3\xb0\x95\xbf')      # volume-low    U+F057F
  cls=""
fi

eww update "volume_text=${icon} ${vol}%" \
           "volume_tooltip=Volume: ${vol}%" \
           "volume_class=${cls}" \
  >/dev/null 2>&1
