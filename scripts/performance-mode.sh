#!/usr/bin/env bash
# Power-profile module for eww. Reads/sets the active profile via
# power-profiles-daemon (powerprofilesctl). `cycle` advances
# balanced(efficient) -> power-saver(battery) -> performance -> balanced.
#
# Glyphs are produced from their Nerd Font UTF-8 bytes via printf '\xNN' so
# the Private-Use-Area characters survive editing/encoding round-trips.
#   fire    U+F0238 (performance boost)
#   leaf    U+F0032 (balanced / efficient)
#   battery U+F0079 (power-saver / battery saver)
G_PERF=$(printf '\xf3\xb0\x88\xb8')
G_BAL=$(printf '\xf3\xb0\x80\xb2')
G_SAVE=$(printf '\xf3\xb0\x81\xb9')

profile() { powerprofilesctl get 2>/dev/null; }

status_json() {
  case "$(profile)" in
    performance)
      printf '{"text":"%s","tooltip":"Performance mode","class":"performance"}\n' "$G_PERF" ;;
    power-saver)
      printf '{"text":"%s","tooltip":"Power-saver mode","class":"power-saver"}\n' "$G_SAVE" ;;
    balanced|*)
      printf '{"text":"%s","tooltip":"Balanced mode","class":"balanced"}\n' "$G_BAL" ;;
  esac
}

# Push current profile state into eww's perf_* vars. Called after a cycle and
# at startup (init) so the widget reflects state without any poll-interval lag.
push_eww() {
  json=$(status_json)
  eww update "perf_text=$(printf '%s' "$json" | jq -r '.text // ""')" \
             "perf_class=$(printf '%s' "$json" | jq -r '.class // ""')" \
             "perf_tooltip=$(printf '%s' "$json" | jq -r '.tooltip // ""')" \
    >/dev/null 2>&1
}

if [ "$1" = "cycle" ]; then
  case "$(profile)" in
    balanced)     next="power-saver" ;;
    power-saver)  next="performance" ;;
    performance)  next="balanced" ;;
    *)            next="balanced" ;;
  esac
  # If the target profile isn't available on this hardware, skip it so the
  # cycle doesn't get stuck (e.g. no 'performance' -> jump to balanced).
  if ! powerprofilesctl set "$next" 2>/dev/null; then
    case "$next" in
      performance) powerprofilesctl set balanced 2>/dev/null ;;
      *)           powerprofilesctl set balanced 2>/dev/null ;;
    esac
  fi
  push_eww   # reflect the new profile in the bar immediately
  exit 0
fi

# Seed the eww vars from the current profile (run once at startup).
if [ "$1" = "init" ]; then
  push_eww
  exit 0
fi

status_json
