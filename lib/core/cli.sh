#!/usr/bin/env bash
# core/cli.sh — subcommand dispatch.
#
# Nearly every executable here is "one script, several verbs"
# (fan-control.sh get|set|cycle|apply|status). Each had its own `case` block
# with its own usage string, and several had no `*)` arm at all — an
# unrecognised verb silently did nothing, or worse, fell into the first
# branch.
#
# A script now declares its verbs as data and gets dispatch, usage and
# arity checking for free. Adding a verb is adding a function and a table
# entry; it never means editing the dispatcher.
#
# Usage:
#     declare -A COMMANDS=(
#       [get]="cmd_get|print the current mode"
#       [set]="cmd_set|<auto|normal|max>  change the mode"
#     )
#     cli::dispatch "${1:-get}" "${@:2}"

hypr::use core/log

# cli::dispatch <verb> [args...] — run the handler for <verb>.
# Requires COMMANDS to be set in the caller's scope.
cli::dispatch() {
  local verb=${1:-} entry handler
  shift || true

  if [[ -z $verb || $verb == -h || $verb == --help || $verb == help ]]; then
    cli::usage
    [[ -z $verb ]] && exit 2 || exit 0
  fi

  entry=${COMMANDS[$verb]:-}
  if [[ -z $entry ]]; then
    log::error "unknown command: $verb"
    cli::usage
    exit 2
  fi

  handler=${entry%%|*}
  "$handler" "$@"
}

# cli::usage — render the command table. Entries are "handler|description",
# where the description may begin with an argument synopsis.
cli::usage() {
  local verb entry description width=0
  for verb in "${!COMMANDS[@]}"; do
    (( ${#verb} > width )) && width=${#verb}
  done
  printf 'usage: %s <command> [args]\n\n' "$HYPR_PROGRAM" >&2
  # Sorted so the help text does not reorder itself between runs (bash
  # associative arrays have no defined iteration order).
  for verb in $(printf '%s\n' "${!COMMANDS[@]}" | sort); do
    entry=${COMMANDS[$verb]}
    description=${entry#*|}
    printf '  %-*s  %s\n' "$width" "$verb" "$description" >&2
  done
}

# cli::need <count> <synopsis> <args...> — assert arity inside a handler.
#     cmd_set() { cli::need 1 "set <auto|normal|max>" "$@"; ... }
cli::need() {
  local required=$1 synopsis=$2; shift 2
  (( $# >= required )) && return 0
  log::usage "$synopsis"
}
