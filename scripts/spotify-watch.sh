#!/usr/bin/env bash
# Long-running process for eww's (deflisten spotify_data ...). Emits fresh
# JSON every 500ms while a spotify player is present, mirroring the old
# GTK Spotify Center's tick loop. Also fetches album art to a local cache.

art_dir="/tmp/spotify-center-art"
mkdir -p "$art_dir"

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

  python3 - "$status" "$title" "$artist" "$album" "$art_path" "${length:-0}" "${position:-0}" <<'PY'
import json
import sys

status, title, artist, album, art_path, length, position = sys.argv[1:8]
length, position = int(length or 0), int(position or 0)

def fmt(micros):
    seconds = max(0, micros // 1_000_000)
    return f"{seconds // 60}:{seconds % 60:02d}"

print(json.dumps({
    "playing": True,
    "status": status,
    "title": title or "Unknown",
    "artist": artist or "Unknown",
    "album": album,
    "art_path": art_path,
    "length_fmt": fmt(length),
    "position_fmt": fmt(position),
    "progress": (position / length) if length > 0 else 0,
    "length_sec": length / 1_000_000 if length else 1,
    "position_sec": position / 1_000_000,
}))
PY
  sleep 0.5
done
