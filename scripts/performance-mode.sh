#!/usr/bin/env bash
# Power-profile module for eww. Reads/sets the active profile via
# power-profiles-daemon (powerprofilesctl). `cycle` advances
# balanced -> performance -> power-saver -> balanced.
#
# Glyphs are produced from their Nerd Font UTF-8 bytes via printf '\xNN' so
# the Private-Use-Area characters survive editing/encoding round-trips.
#   speedometer        U+F04C5 (performance)
#   speedometer-medium U+F04C4 (balanced)
#   speedometer-slow   U+F04C3 (power-saver)
G_PERF=$(printf '\xf3\xb0\x93\x85')
G_BAL=$(printf '\xf3\xb0\x93\x84')
G_SAVE=$(printf '\xf3\xb0\x93\x83')

profile() { powerprofilesctl get 2>/dev/null; }

status_json() {
  case "$(profile)" in
    performance)
      printf '{"text":"%s","tooltip":"Performance mode","class":"performance"}\n' "$G_PERF" ;;
    power-saver)
      printf '{"text":"%s","tooltip":"Power-saver mode","class":"balanced"}\n' "$G_SAVE" ;;
    balanced|*)
      printf '{"text":"%s","tooltip":"Balanced mode","class":"balanced"}\n' "$G_BAL" ;;
  esac
}

if [ "$1" = "cycle" ]; then
  case "$(profile)" in
    balanced)     next="performance" ;;
    performance)  next="power-saver" ;;
    power-saver)  next="balanced" ;;
    *)            next="balanced" ;;
  esac
  powerprofilesctl set "$next" 2>/dev/null || powerprofilesctl set balanced 2>/dev/null
  # push fresh state into eww immediately
  json=$(status_json)
  eww update "perf_text=$(printf '%s' "$json" | jq -r '.text // ""')" \
             "perf_class=$(printf '%s' "$json" | jq -r '.class // ""')" \
             "perf_tooltip=$(printf '%s' "$json" | jq -r '.tooltip // ""')" \
    >/dev/null 2>&1
  exit 0
fi

status_json
