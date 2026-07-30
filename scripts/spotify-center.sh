#!/usr/bin/env bash
#
# Compact Spotify dropdown (rofi).
# Layout: [ art | title/artist/progress/times + prev · play/pause · next ]

set -euo pipefail

THEME=/home/prieyan/.config/hypr/apps/rofi/spotify.rasi
PLAYER=spotify
ART_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/hypr-spotify-art.jpg"
ART_URL_FILE="${ART_CACHE}.url"
FALLBACK_ART=/home/prieyan/.config/hypr/apps/rofi/spotify-fallback.png

# Toggle: second click closes.
if pgrep -x rofi >/dev/null 2>&1 && pgrep -af '[r]ofi' | grep -q 'spotify\.rasi'; then
  pkill -f '[r]ofi.*spotify\.rasi' >/dev/null 2>&1 || true
  exit 0
fi

pc() { playerctl -p "$PLAYER" "$@" >/dev/null 2>&1; }

refresh_waybar() {
  pkill -RTMIN+10 waybar >/dev/null 2>&1 || true
}

fmt_time() {
  local s=${1%.*}
  s=${s:-0}
  (( s < 0 )) && s=0
  printf '%d:%02d' $((s / 60)) $((s % 60))
}

progress_bar() {
  local pos=${1%.*}
  local len=${2%.*}
  pos=${pos:-0}
  len=${len:-1}
  (( len < 1 )) && len=1

  local pct=$((pos * 100 / len))
  (( pct > 100 )) && pct=100
  (( pct < 0 )) && pct=0

  local width=22
  local filled=$((pct * width / 100))
  local empty=$((width - filled))
  local i bar=""
  for ((i = 0; i < filled; i++)); do bar+="━"; done
  for ((i = 0; i < empty; i++)); do bar+="─"; done
  printf '%s' "$bar"
}

cache_art() {
  local url=$1
  [ -z "$url" ] && return 0
  case "$url" in
    file://*)
      local src=${url#file://}
      [ -f "$src" ] && printf '%s' "$src"
      ;;
    http://*|https://*)
      local prev
      prev=$(cat "$ART_URL_FILE" 2>/dev/null || true)
      if [ "$prev" != "$url" ] || [ ! -s "$ART_CACHE" ]; then
        if curl -fsSL --max-time 3 "$url" -o "${ART_CACHE}.tmp" 2>/dev/null; then
          mv -f "${ART_CACHE}.tmp" "$ART_CACHE"
          printf '%s' "$url" >"$ART_URL_FILE"
        fi
      fi
      [ -s "$ART_CACHE" ] && printf '%s' "$ART_CACHE"
      ;;
  esac
}

xml_escape() {
  printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

ensure_fallback() {
  [ -s "$FALLBACK_ART" ] && return 0
  # tiny dark placeholder PNG
  printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=' \
    | base64 -d >"$FALLBACK_ART" 2>/dev/null || true
}

show() {
  local status title artist art_url length_us length position art toggle bar rem info choice

  status=$(playerctl -p "$PLAYER" status 2>/dev/null || true)
  if [ -z "$status" ] || [ "$status" = "Stopped" ]; then
    printf '%s\n' "Close" \
      | rofi -dmenu -mesg "Nothing playing" -theme "$THEME" -no-custom \
          -theme-str 'mainbox { children: [ body ]; } icon { enabled: false; }' \
          >/dev/null || true
    exit 0
  fi

  title=$(playerctl -p "$PLAYER" metadata xesam:title 2>/dev/null || echo Unknown)
  artist=$(playerctl -p "$PLAYER" metadata xesam:artist 2>/dev/null || echo Unknown)
  art_url=$(playerctl -p "$PLAYER" metadata mpris:artUrl 2>/dev/null || true)
  length_us=$(playerctl -p "$PLAYER" metadata mpris:length 2>/dev/null || echo 0)
  position=$(playerctl -p "$PLAYER" position 2>/dev/null || echo 0)
  length=$(( ${length_us:-0} / 1000000 ))
  (( length < 1 )) && length=1

  ensure_fallback
  art=$(cache_art "$art_url" || true)
  [ -z "${art:-}" ] && art=$FALLBACK_ART

  bar=$(progress_bar "$position" "$length")
  rem=$((length - ${position%.*}))
  (( rem < 0 )) && rem=0

  pos_s=$(fmt_time "$position")
  rem_s=$(fmt_time "$rem")
  # Title / artist / progress /  elapsed …… -remaining
  info=$(printf '<b>%s</b>\n<span foreground="#888888">%s</span>\n%s\n<span foreground="#888888">%s&#9;&#9;&#9;&#9;-%s</span>' \
    "$(xml_escape "$title")" \
    "$(xml_escape "$artist")" \
    "$bar" \
    "$pos_s" \
    "$rem_s")

  if [ "$status" = "Playing" ]; then
    toggle="󰏤"
  else
    toggle="󰐊"
  fi

  choice=$(
    printf '%s\n' "󰒮" "$toggle" "󰒭" | rofi -dmenu \
      -markup-rows \
      -mesg "$info" \
      -theme "$THEME" \
      -theme-str "icon { filename: \"$art\"; }" \
      -selected-row 1 \
      -format i \
      -no-custom \
      -p ""
  ) || exit 0

  case "$choice" in
    0) pc previous;   refresh_waybar; show ;;
    1) pc play-pause; refresh_waybar; show ;;
    2) pc next;       refresh_waybar; show ;;
    *) exit 0 ;;
  esac
}

show
