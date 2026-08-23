#!/usr/bin/env bash


# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../scripts" && pwd)/_paths.sh"
STATE_FILE="$HOME/.cache/hypr_brightness_boost"

# Eye comfort (hyprsunset -t) turns the icon yellow. The ^ anchor keeps the
# pattern from matching this script's own shell.
if pgrep -af '^hyprsunset .*-t' >/dev/null 2>&1; then
  EYE_CLASS="eye-comfort"
else
  EYE_CLASS=""
fi

if command -v brightnessctl >/dev/null 2>&1; then
  value=$(brightnessctl g 2>/dev/null || echo "100")
  max=$(brightnessctl m 2>/dev/null || echo "100")
  percent=$((100 * value / max))
  
  # Read software boost
  if [ -f "$STATE_FILE" ]; then
    boost=$(cat "$STATE_FILE")
  else
    boost="1.0"
  fi
  
  # Sanity check
  if [[ ! "$boost" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    boost="1.0"
  fi
  
  # Check if boost is active (greater than 1.0)
  BOOST_ACTIVE=$(awk "BEGIN {print ($boost > 1.0) ? 1 : 0}")
  
  if [ "$BOOST_ACTIVE" -eq 1 ]; then
    # Calculate boosted percentage (e.g. 1.25 -> 125%)
    percent_boosted=$(awk "BEGIN {print int($boost * 100)}")
    icon='⚡ '
    echo '{"text":"'"$icon $percent_boosted%"'","tooltip":"Super Brightness Active! Level: '"$percent_boosted"'%","class":["boosted"'"${EYE_CLASS:+,\"$EYE_CLASS\"}"']}'
  else
    icon=''
    echo '{"text":"'"$icon $percent%"'","tooltip":"Use scroll to adjust brightness'"${EYE_CLASS:+ | Eye comfort on}"'","class":['"${EYE_CLASS:+\"$EYE_CLASS\"}"']}'
  fi
else
  echo '{"text":" n/a","tooltip":"Install brightnessctl for real brightness control"}'
fi
