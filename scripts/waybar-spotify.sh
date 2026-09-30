#!/usr/bin/env bash


# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

if [ "$1" = "menu" ]; then
  # The card is a quickshell daemon (apps/quickshell/spotify/shell.qml), so a
  # click is just an IPC toggle against the already-running surface. There is
  # no rofi fallback any more — the old popup could not redraw without exiting
  # and relaunching, which is what made it flicker and close on its own.
  "${HYPR_SCRIPTS}/qs-toggle.sh" spotify spotify && exit 0

  command -v notify-send >/dev/null 2>&1 \
    && notify-send -a "Spotify" "Media card unavailable" "quickshell is not running."
  exit 1
fi

if [ "$1" = "toggle" ]; then
  playerctl -p spotify play-pause >/dev/null 2>&1
  exit 0
fi

status=$(playerctl -p spotify status 2>/dev/null)
if [ -z "$status" ] || [ "$status" = "Stopped" ]; then
  printf '{"text":"","tooltip":"Spotify: not playing"}\n'
  exit 0
fi

title=$(playerctl -p spotify metadata xesam:title 2>/dev/null)
artist=$(playerctl -p spotify metadata xesam:artist 2>/dev/null)
[ -z "$title" ] && title="Unknown"
[ -z "$artist" ] && artist="Unknown"

icon=""
[ "$status" = "Paused" ] && icon=""

label="$title — $artist"
label_json=$(json_escape "$label")
tip_json=$(json_escape "$status: $title — $artist")
printf '{"text":"%s  %s","tooltip":"%s","class":"%s"}\n' "$icon" "$label_json" "$tip_json" "$(printf '%s' "$status" | tr '[:upper:]' '[:lower:]')"
