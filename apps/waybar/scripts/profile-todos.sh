#!/usr/bin/env bash
# Tiny JSON-backed todo store for the profile dropdown.
# Usage: profile-todos.sh list|add TEXT|toggle INDEX|remove INDEX
#
# The on-disk format is unchanged from the previous Python implementation:
# [{"text": "...", "done": false}, ...]

STORE="$HOME/.local/share/hypr/profile-todos.json"

load() {
  # An unreadable or corrupt store degrades to empty, as before.
  if [ -f "$STORE" ] && jq -e . "$STORE" >/dev/null 2>&1; then
    cat "$STORE"
  else
    echo '[]'
  fi
}

save() {
  mkdir -p "$(dirname "$STORE")"
  # Write via temp file so a crash mid-write cannot truncate the store.
  tmp=$(mktemp "${STORE}.XXXXXX") || exit 1
  printf '%s\n' "$1" | jq --indent 2 . > "$tmp" && mv -f "$tmp" "$STORE" || rm -f "$tmp"
}

todos=$(load)
cmd="${1:-list}"

case "$cmd" in
  list)
    printf '%s' "$todos" | jq -r '.[] | "[" + (if .done then "x" else " " end) + "] " + .text'
    ;;
  add)
    [ -n "$2" ] || exit 0
    save "$(printf '%s' "$todos" | jq --arg t "$2" '. + [{text:$t, done:false}]')"
    ;;
  toggle)
    [ -n "$2" ] || exit 0
    save "$(printf '%s' "$todos" | jq --argjson i "$2" \
      'if $i >= 0 and $i < length then .[$i].done |= (. | not) else . end')"
    ;;
  remove)
    [ -n "$2" ] || exit 0
    save "$(printf '%s' "$todos" | jq --argjson i "$2" \
      'if $i >= 0 and $i < length then del(.[$i]) else . end')"
    ;;
esac
