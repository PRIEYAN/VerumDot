#!/usr/bin/env bash
# Adjust output volume via pamixer and push the new % straight into eww in a
# SINGLE update — no separate status-script/jq round-trip — so rapid scrolling
# stays smooth. Usage: volume-adjust.sh up|down

case "$1" in
  up)   pamixer -i 5 ;;
  down) pamixer -d 5 ;;
esac

muted=$(pamixer --get-mute 2>/dev/null)
vol=$(pamixer --get-volume 2>/dev/null)

if [ "$muted" = "true" ]; then
  icon=$(printf '\xf3\xb0\x9d\x9f')      # volume-mute   U+F075F
  cls="muted"
elif [ "${vol:-0}" -ge 66 ]; then
  icon=$(printf '\xf3\xb0\x95\xbe')      # volume-high   U+F057E
  cls=""
elif [ "${vol:-0}" -ge 33 ]; then
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
