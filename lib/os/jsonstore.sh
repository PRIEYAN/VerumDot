#!/usr/bin/env bash
# os/jsonstore.sh — a small JSON document on disk, written atomically.
#
# The todo list and the stopwatch each had their own load/save pair with the
# same shape and the same two rules: a corrupt or unreadable store degrades
# to a default rather than erroring, and a write goes through a temporary
# file so a crash mid-write cannot truncate it.

hypr::use core/guard core/log core/paths

# jsonstore::path <name> — documents live in the data tree: they are user
# content, not regenerable cache and not runtime scratch.
jsonstore::path() { printf '%s/%s.json' "$HYPR_DATA_DIR" "$1"; }

# jsonstore::load <name> <default-json> — the document, or the default when
# it is missing, unreadable or not valid JSON.
jsonstore::load() {
  local file; file=$(jsonstore::path "$1")
  if [[ -f $file ]] && jq -e . "$file" >/dev/null 2>&1; then
    cat -- "$file"
  else
    printf '%s' "$2"
  fi
}

# jsonstore::save <name> <json> — replace the document atomically.
# The content is piped through jq, so an invalid document is rejected before
# it can overwrite a good one.
jsonstore::save() {
  local file tmp; file=$(jsonstore::path "$1")
  mkdir -p -- "$HYPR_DATA_DIR"
  tmp=$(mktemp "${file}.XXXXXX") || return 1
  if printf '%s\n' "$2" | jq --indent 2 . >"$tmp"; then
    mv -f -- "$tmp" "$file"
  else
    rm -f -- "$tmp"
    log::error "refused to save invalid JSON to ${file}"
    return 1
  fi
}

# jsonstore::update <name> <default> <jq-filter> [jq-args...] — load, apply a
# filter, save. The read-modify-write every caller was spelling out.
jsonstore::update() {
  local name=$1 fallback=$2 filter=$3; shift 3
  local current updated
  current=$(jsonstore::load "$name" "$fallback")
  updated=$(printf '%s' "$current" | jq -c "$@" "$filter") || return 1
  jsonstore::save "$name" "$updated"
}
