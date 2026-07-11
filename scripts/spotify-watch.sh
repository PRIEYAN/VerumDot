#!/usr/bin/env bash
# Long-running process for eww's (deflisten spotify_data ...). Emits fresh
# JSON every 500ms while a spotify player is present, mirroring the old
# GTK Spotify Center's tick loop. Also fetches album art to a local cache.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/json.sh"

art_dir="${XDG_RUNTIME_DIR:-/tmp}/spotify-center-art"
mkdir -p "$art_dir"

# micros -> "m:ss" (integer math only).
fmt_time() {
  local micros=$1
  [ -n "$micros" ] && [ "$micros" -ge 0 ] 2>/dev/null || micros=0
  local seconds=$(( micros / 1000000 ))
  printf '%d:%02d' "$(( seconds / 60 ))" "$(( seconds % 60 ))"
}

fetch_art() {
  local url="$1"
  [ -z "$url" ] && return
  local hash
  hash=$(printf '%s' "$url" | md5sum | cut -d' ' -f1)
  local path="$art_dir/$hash.img"
  if [ ! -f "$path" ]; then
    if [[ "$url" == file://* ]]; then
      cp "${url#file://}" "$path" 2>/dev/null
    else
      curl -fsSL "$url" -o "$path" 2>/dev/null
    fi
  fi
  [ -f "$path" ] && printf '%s' "$path"
}

while true; do
  status=$(playerctl -p spotify status 2>/dev/null)
  if [ -z "$status" ] || [ "$status" = "Stopped" ]; then
    printf '{"playing":false}\n'
    sleep 0.5
    continue
  fi

  IFS=$'\t' read -r title artist album art_url length position <<< "$(playerctl -p spotify metadata --format '{{title}}	{{artist}}	{{album}}	{{mpris:artUrl}}	{{mpris:length}}	{{position}}' 2>/dev/null)"
  art_path=$(fetch_art "$art_url")

  # Normalise the raw micros to integers (empty/garbage -> 0).
  length=${length:-0}; position=${position:-0}
  case $length in ''|*[!0-9]*) length=0 ;; esac
  case $position in ''|*[!0-9]*) position=0 ;; esac

  # length_sec must be >= 1 so eww's scale :max is never 0.
  length_sec=$(( length / 1000000 )); [ "$length_sec" -lt 1 ] && length_sec=1
  position_sec=$(( position / 1000000 ))
  # progress as an integer percent (0..100); the widget doesn't read it, but
  # keep the field for compatibility with the previous JSON shape.
  if [ "$length" -gt 0 ]; then progress=$(( position * 100 / length )); else progress=0; fi

  printf '{"playing":true,"status":%s,"title":%s,"artist":%s,"album":%s,"art_path":%s,"length_fmt":%s,"position_fmt":%s,"progress":%d,"length_sec":%d,"position_sec":%d}\n' \
    "$(json_str "$status")" \
    "$(json_str "${title:-Unknown}")" \
    "$(json_str "${artist:-Unknown}")" \
    "$(json_str "$album")" \
    "$(json_str "$art_path")" \
    "$(json_str "$(fmt_time "$length")")" \
    "$(json_str "$(fmt_time "$position")")" \
    "$progress" "$length_sec" "$position_sec"
  sleep 0.5
done
