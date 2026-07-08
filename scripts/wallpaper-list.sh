#!/usr/bin/env bash
# Emits JSON array of wallpaper files (name + path) for eww's Wallpaper Center.
# Usage: wallpaper-list.sh [filter-substring]

dir="$HOME/Pictures/Wallpapers"
filter="${1:-}"

if [ ! -d "$dir" ]; then
  echo "[]"
  exit 0
fi

shopt -s nullglob nocaseglob
files=("$dir"/*.jpg "$dir"/*.jpeg "$dir"/*.png "$dir"/*.webp)
shopt -u nullglob nocaseglob

python3 - "$filter" "${files[@]}" <<'PY'
import json
import os
import sys

filter_ = sys.argv[1].lower()
files = sorted(sys.argv[2:], key=lambda p: os.path.basename(p).lower())

items = [
    {"name": os.path.splitext(os.path.basename(p))[0].lower(), "path": p}
    for p in files
    if filter_ in os.path.basename(p).lower()
]
rows = [items[i:i + 3] for i in range(0, len(items), 3)]
print(json.dumps({"count": len(items), "rows": rows}))
PY
