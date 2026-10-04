#!/usr/bin/env bash
# Todo store behind the profile dropdown.
#
# The on-disk shape is unchanged: [{"text": "...", "done": false}, ...]

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/cli os/jsonstore

readonly STORE=profile-todos
readonly EMPTY='[]'

# Index guards live in the jq filters rather than in shell: an out-of-range
# index leaves the document untouched instead of producing `null` entries.
cmd_list() {
  jsonstore::load "$STORE" "$EMPTY" \
    | jq -r '.[] | "[" + (if .done then "x" else " " end) + "] " + .text'
}

cmd_add() {
  [[ -n ${1:-} ]] || return 0
  jsonstore::update "$STORE" "$EMPTY" '. + [{text: $t, done: false}]' --arg t "$1"
}

cmd_toggle() {
  [[ -n ${1:-} ]] || return 0
  jsonstore::update "$STORE" "$EMPTY" \
    'if $i >= 0 and $i < length then .[$i].done |= (. | not) else . end' --argjson i "$1"
}

cmd_remove() {
  [[ -n ${1:-} ]] || return 0
  jsonstore::update "$STORE" "$EMPTY" \
    'if $i >= 0 and $i < length then del(.[$i]) else . end' --argjson i "$1"
}

declare -A COMMANDS=(
  [list]="cmd_list|print the todo list (the default)"
  [add]="cmd_add|<text>  append a todo"
  [toggle]="cmd_toggle|<index>  mark done/undone"
  [remove]="cmd_remove|<index>  delete a todo"
)

cli::dispatch "${1:-list}" "${@:2}"
