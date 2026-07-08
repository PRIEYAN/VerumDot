#!/usr/bin/env bash
# Power-profile module for eww. Reads/sets the active profile via
# power-profiles-daemon (powerprofilesctl). `cycle` advances
# balanced -> performance -> power-saver -> balanced.
#
# Output (no arg): JSON {text, class, tooltip} for the bar.

profile() { powerprofilesctl get 2>/dev/null; }

if [ "$1" = "cycle" ]; then
  case "$(profile)" in
    balanced)     next="performance" ;;
    performance)  next="power-saver" ;;
    power-saver)  next="balanced" ;;
    *)            next="balanced" ;;
  esac
  # Fall back gracefully if the daemon lacks the target profile.
  powerprofilesctl set "$next" 2>/dev/null || powerprofilesctl set balanced 2>/dev/null
  exit 0
fi

case "$(profile)" in
  performance)
    printf '{"text":"","tooltip":"Performance mode","class":"performance"}\n' ;;
  power-saver)
    printf '{"text":"","tooltip":"Power-saver mode","class":"balanced"}\n' ;;
  balanced|*)
    printf '{"text":"","tooltip":"Balanced mode","class":"balanced"}\n' ;;
esac
