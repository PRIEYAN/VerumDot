#!/usr/bin/env bash
# Emits JSON array of wallpaper files (name + thumbnail path) for eww's
# Wallpaper Center. Thumbnails are generated once and cached, so the window
# opens fast even with many large wallpapers.
# Usage: wallpaper-list.sh [filter-substring]

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

# Build "name<TAB>thumb<TAB>fullpath" lines, filtered, then hand to python
# for JSON assembly (python handles quoting/rows).
tmp=$(mktemp)
for f in "${files[@]}"; do
  base=$(basename "$f")
  case "${base,,}" in
    *"${filter,,}"*) printf '%s\t%s\t%s\n' "${base%.*}" "$(thumb_for "$f")" "$f" >> "$tmp" ;;
  esac
done

python3 - "$tmp" <<'PY'
import json, sys
items = []
with open(sys.argv[1]) as fh:
    for line in fh:
        parts = line.rstrip("\n").split("\t")
        if len(parts) == 3:
            name, thumb, full = parts
            items.append({"name": name.lower(), "path": thumb, "full": full})
items.sort(key=lambda x: x["name"])
rows = [items[i:i+3] for i in range(0, len(items), 3)]
print(json.dumps({"count": len(items), "rows": rows}))
PY
rm -f "$tmp"
