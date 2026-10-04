#!/usr/bin/env bash
# os/ini.sh — idempotent edits to INI files owned by other programs.
#
# qt5ct.conf, kdeglobals and dolphinrc hold the user's own settings
# alongside the few keys this theme needs, so they are edited key by key
# rather than replaced.

hypr::use core/log

# ini::set <file> <section> <key> <value>
#
# Creates the file, the section, or the key as needed, and replaces the key
# in place when it already exists *within that section* — a key of the same
# name under a different section must not be touched.
ini::set() {
  local file=$1 section=$2 key=$3 value=$4 tmp

  if [[ ! -f $file ]]; then
    mkdir -p -- "$(dirname -- "$file")"
    printf '[%s]\n%s=%s\n' "$section" "$key" "$value" >"$file"
    return 0
  fi

  if ! grep -q "^\[${section}\]" "$file"; then
    printf '\n[%s]\n%s=%s\n' "$section" "$key" "$value" >>"$file"
    return 0
  fi

  tmp="${file}.$$.tmp"
  awk -v section="[$section]" -v key="$key" -v value="$value" '
    BEGIN { inside = 0; replaced = 0 }
    $0 == section { print; inside = 1; next }
    /^\[/         { if (inside && !replaced) { print key "=" value; replaced = 1 }
                    inside = 0 }
    inside && index($0, key "=") == 1 { print key "=" value; replaced = 1; next }
    { print }
    END { if (inside && !replaced) print key "=" value }
  ' "$file" >"$tmp" && mv -f -- "$tmp" "$file"
}
