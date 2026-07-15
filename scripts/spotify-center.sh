#!/usr/bin/env bash
#
# Spotify center. Now-playing info and transport controls in a rofi menu.
# Pure shell -- no python, no GTK, no album-art window. Refreshes the
# waybar module after each action.

THEME=/home/prieyan/.config/hypr/apps/rofi/waybar-menu.rasi
PLAYER=spotify

pc() {
  playerctl -p "$PLAYER" "$@" >/dev/null 2>&1
}

meta() {
  playerctl -p "$PLAYER" metadata --format "$1" 2>/dev/null
}

refresh_waybar() {
  pkill -RTMIN+10 waybar >/dev/null 2>&1
}

show() {
  status=$(playerctl -p "$PLAYER" status 2>/dev/null)
  if [ -z "$status" ] || [ "$status" = "Stopped" ]; then
    printf '%s\n' "  nothing playing" "  close" \
      | rofi -dmenu -p "Spotify" -theme "$THEME" >/dev/null
    exit 0
  fi

  title=$(meta '{{title}}')
  artist=$(meta '{{artist}}')
  album=$(meta '{{album}}')
  [ -z "$title" ] && title="Unknown"
  [ -z "$artist" ] && artist="Unknown"

  toggle="  play"
  [ "$status" = "Playing" ] && toggle="  pause"

  choice=$(printf '%s\n' \
    "  $title" \
    "  $artist" \
    "  $album" \
    "" \
    "󰒮  previous" \
    "$toggle" \
    "󰒭  next" \
    "  close" \
    | rofi -dmenu -p "Spotify" -theme "$THEME")

  case "$choice" in
    *previous*)   pc previous; refresh_waybar; show ;;
    *play*|*pause*) pc play-pause; refresh_waybar; show ;;
    *next*)       pc next; refresh_waybar; show ;;
    *close*)      exit 0 ;;
    *)            exit 0 ;;
  esac
}

show
