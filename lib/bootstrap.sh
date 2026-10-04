#!/usr/bin/env bash
# bootstrap.sh — the single entry point into the shared library.
#
# Every executable in this rice begins with the same three-line preamble:
#
#     _dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
#     while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
#     source "$_dir/lib/bootstrap.sh"
#
# The walk upwards is what makes the preamble *identical* at every depth —
# scripts/, scripts/eww/ and apps/waybar/scripts/ all use the same three
# lines, which the previous three hand-maintained `../..` variants did not.
#
# Having found the library, a script declares what it needs:
#
#     hypr::use ui/rofi ui/notify domain/network
#
# and nothing more. Modules are loaded once, in dependency order, and are
# free to `hypr::use` their own dependencies.

# Guard against double-sourcing (a script may be exec'd by another).
[[ -n "${HYPR_BOOTSTRAPPED:-}" ]] && return 0
readonly HYPR_BOOTSTRAPPED=1

# ---------------------------------------------------------------------------
# Strict mode
# ---------------------------------------------------------------------------
# `pipefail` without `errexit`: these scripts query hardware and daemons that
# are legitimately allowed to fail, and each call site decides what a failure
# means. `nounset` stays on — an unset variable is always a bug here.
set -uo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# ---------------------------------------------------------------------------
# Library root
# ---------------------------------------------------------------------------
HYPR_LIB=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
readonly HYPR_LIB
readonly HYPR_HOME="${HYPR_LIB%/lib}"

# Name of the running script, used by the logger and by notifications.
HYPR_PROGRAM=${HYPR_PROGRAM:-$(basename -- "${BASH_SOURCE[${#BASH_SOURCE[@]} - 1]}")}
readonly HYPR_PROGRAM

# ---------------------------------------------------------------------------
# Module loader
# ---------------------------------------------------------------------------
declare -Ag _HYPR_LOADED=()

# hypr::use <module>... — load library modules by path relative to lib/,
# without the .sh suffix. Idempotent; safe to call from inside a module.
hypr::use() {
  local module path
  for module in "$@"; do
    [[ -n "${_HYPR_LOADED[$module]:-}" ]] && continue
    path="${HYPR_LIB}/${module}.sh"
    if [[ ! -r "$path" ]]; then
      printf '%s: no such library module: %s\n' "$HYPR_PROGRAM" "$module" >&2
      return 1
    fi
    # Marked before sourcing so a dependency cycle terminates instead of
    # recursing until the shell dies.
    _HYPR_LOADED[$module]=1
    # shellcheck source=/dev/null
    source "$path"
  done
}

# The three modules every script is entitled to assume are present.
hypr::use core/paths core/log core/guard
