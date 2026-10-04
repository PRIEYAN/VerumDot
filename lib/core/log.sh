#!/usr/bin/env bash
# core/log.sh — diagnostics, on stderr, never on stdout.
#
# This matters more here than in an ordinary program: several of these
# scripts ARE a protocol. A waybar module's stdout must be one JSON object
# and nothing else, and a rofi menu's stdout is the menu itself. A stray
# `echo "debugging..."` corrupts both. Routing every diagnostic through this
# module makes that impossible by construction.
#
# Verbosity is controlled by HYPR_LOG_LEVEL (debug|info|warn|error|silent),
# defaulting to warn so a normal session is quiet.

declare -Ag _LOG_WEIGHT=([debug]=10 [info]=20 [warn]=30 [error]=40 [silent]=99)

_log_threshold() {
  local level=${HYPR_LOG_LEVEL:-warn}
  printf '%s' "${_LOG_WEIGHT[$level]:-30}"
}

_log_emit() {
  local level=$1 weight=$2; shift 2
  (( weight < $(_log_threshold) )) && return 0
  printf '%s: [%s] %s\n' "$HYPR_PROGRAM" "$level" "$*" >&2
}

log::debug() { _log_emit debug 10 "$@"; }
log::info()  { _log_emit info  20 "$@"; }
log::warn()  { _log_emit warn  30 "$@"; }
log::error() { _log_emit error 40 "$@"; }

# log::die [-c <code>] <message>... — report and exit.
# The default exit code is 1; `-c 0` lets a caller bail out quietly after
# saying why (used where "nothing to do" is a normal outcome).
log::die() {
  local code=1
  if [[ ${1:-} == -c ]]; then code=$2; shift 2; fi
  if (( code == 0 )); then log::info "$@"; else log::error "$@"; fi
  exit "$code"
}

# log::usage <synopsis> — the one-line usage error every dispatcher needs.
# Exits 2, the conventional code for a command-line fault.
log::usage() {
  printf 'usage: %s %s\n' "$HYPR_PROGRAM" "$1" >&2
  exit 2
}
