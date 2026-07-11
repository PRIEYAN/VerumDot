#!/usr/bin/env bash
# Emits JSON array of wallpaper files (name + thumbnail path) for eww's
# Wallpaper Center. Thumbnails are generated once and cached, so the window
# opens fast even with many large wallpapers.
# Usage: wallpaper-list.sh [filter-substring]

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/json.sh"

dir="$HOME/Pictures/Wallpapers"
cache="$HOME/.cache/eww-wallpaper-thumbs"
filter="${1:-}"

[ -d "$dir" ] || { echo '{"count":0,"rows":[]}'; exit 0; }
mkdir -p "$cache"

# Pick a thumbnailer once.
if command -v magick >/dev/null 2>&1;   then THUMB=magick
elif command -v convert >/dev/null 2>&1; then THUMB=convert
elif command -v ffmpeg >/dev/null 2>&1;  then THUMB=ffmpeg
else THUMB=none
fi

# Generate a ~400px-wide thumbnail if missing/stale; echo the path to use
# (falls back to the original if no thumbnailer is available).
thumb_for() {
  local src="$1" key out
  key=$(printf '%s' "$src" | md5sum | cut -d' ' -f1)
  out="$cache/$key.png"
  if [ "$THUMB" = none ]; then printf '%s' "$src"; return; fi
  if [ ! -f "$out" ] || [ "$src" -nt "$out" ]; then
    case "$THUMB" in
      magick)  magick "$src" -thumbnail 400x225^ -gravity center -extent 400x225 "$out" >/dev/null 2>&1 ;;
      convert) convert "$src" -thumbnail 400x225^ -gravity center -extent 400x225 "$out" >/dev/null 2>&1 ;;
      ffmpeg)  ffmpeg -y -i "$src" -vf "scale=400:-1" "$out" >/dev/null 2>&1 ;;
    esac
  fi
  [ -f "$out" ] && printf '%s' "$out" || printf '%s' "$src"
}

shopt -s nullglob nocaseglob
files=("$dir"/*.jpg "$dir"/*.jpeg "$dir"/*.png "$dir"/*.webp)
shopt -u nullglob nocaseglob

# Build "name<TAB>thumb<TAB>fullpath" lines (name lowercased for sort+display),
# filtered, then assemble JSON in pure shell — rows of 3 items each.
# NOTE: precompute the lowercased filter into a plain var — a *quoted* empty
# expansion (*"${filter,,}"*) fails to match everything in bash 5.2, so use
# the pattern unquoted with the empty string matching all names.
flt=${filter,,}
tmp=$(mktemp)
for f in "${files[@]}"; do
  base=$(basename "$f")
  case "${base,,}" in
    *$flt*)
      name=${base%.*}
      printf '%s\t%s\t%s\n' "${name,,}" "$(thumb_for "$f")" "$f" >> "$tmp"
      ;;
  esac
done

# Sort by name (first TAB-separated field), then emit {count, rows[[{...}]]}.
count=0
rows=""      # comma-joined week/row arrays
cell_json="" # items accumulated for the current row of 3
col=0
while IFS=$'\t' read -r name thumb full; do
  [ -n "$name$thumb$full" ] || continue
  count=$(( count + 1 ))
  item=$(printf '{"name":%s,"path":%s,"full":%s}' \
    "$(json_str "$name")" "$(json_str "$thumb")" "$(json_str "$full")")
  if [ -z "$cell_json" ]; then cell_json="$item"; else cell_json="$cell_json,$item"; fi
  col=$(( col + 1 ))
  if [ "$col" -eq 3 ]; then
    if [ -z "$rows" ]; then rows="[$cell_json]"; else rows="$rows,[$cell_json]"; fi
    cell_json=""; col=0
  fi
done < <(LC_ALL=C sort -t $'\t' -k1,1 "$tmp")
# Flush a partial final row.
if [ -n "$cell_json" ]; then
  if [ -z "$rows" ]; then rows="[$cell_json]"; else rows="$rows,[$cell_json]"; fi
fi
rm -f "$tmp"

printf '{"count":%d,"rows":[%s]}\n' "$count" "$rows"
