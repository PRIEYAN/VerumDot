#!/usr/bin/env bash
# Tiny JSON helpers so the eww scripts can build valid JSON in pure shell
# (no external tools). Source this file:  . "$DIR/json.sh"
#
# json_escape "<raw string>"   -> prints the string escaped for a JSON
#                                 *value*, WITHOUT surrounding quotes.
# json_str    "<raw string>"   -> prints the string as a quoted JSON string.
#
# Escapes the characters JSON requires: backslash, double-quote, and the
# control range (U+0000–U+001F) — the usual offenders in song titles,
# SSIDs and Bluetooth device names.

# Escape a single string for embedding in JSON (no surrounding quotes).
json_escape() {
  local s=$1
  # Order matters: backslash first so we don't double-escape the ones we add.
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  # Common control characters with short escapes.
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  s=${s//$'\f'/\\f}
  s=${s//$'\b'/\\b}
  # Any remaining C0 control chars → \u00XX. Handle the ones that survive
  # (e.g. NUL can't appear in a bash var, but ESC/VT/etc. can).
  local out="" c i rest=$s
  case $rest in
    *[$'\x01'-$'\x1f']*)
      out=""
      for (( i=0; i<${#rest}; i++ )); do
        c=${rest:i:1}
        case $c in
          [$'\x01'-$'\x1f'])
            printf -v c '\\u%04x' "'$c"
            ;;
        esac
        out+=$c
      done
      s=$out
      ;;
  esac
  printf '%s' "$s"
}

# Print a raw string as a complete quoted JSON string.
json_str() {
  printf '"%s"' "$(json_escape "$1")"
}
