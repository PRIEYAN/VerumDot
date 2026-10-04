#!/usr/bin/env bash
# core/guard.sh — preconditions.
#
# Replaces the thirty-odd hand-written `command -v foo >/dev/null 2>&1`
# guards that were scattered through the scripts, each with its own idea of
# what to do when the tool was missing (some exited, some printed to stdout
# and corrupted a waybar module, most said nothing at all).

# guard::has <command>... — true only if every command exists. Silent.
guard::has() {
  local cmd
  for cmd in "$@"; do
    command -v -- "$cmd" >/dev/null 2>&1 || return 1
  done
  return 0
}

# guard::require <command>... — every command must exist, or exit 127 with a
# message naming what to install. For hard dependencies.
guard::require() {
  local cmd missing=()
  for cmd in "$@"; do
    guard::has "$cmd" || missing+=("$cmd")
  done
  (( ${#missing[@]} == 0 )) && return 0
  log::die -c 127 "missing required command(s): ${missing[*]}"
}

# guard::readable <path>... / guard::writable <path>...
# Used before touching sysfs nodes, which exist or not depending on the
# hardware and are writable or not depending on whether the udev rules are
# installed.
guard::readable() {
  local p
  for p in "$@"; do [[ -r $p ]] || return 1; done
  return 0
}

guard::writable() {
  local p
  for p in "$@"; do [[ -w $p ]] || return 1; done
  return 0
}

# guard::one_of <value> <allowed>... — validate an enum argument, echoing the
# value back on success so it can be used inline:
#     mode=$(guard::one_of "$1" auto normal max) || log::usage '...'
guard::one_of() {
  local value=$1 candidate; shift
  for candidate in "$@"; do
    [[ $value == "$candidate" ]] && { printf '%s' "$value"; return 0; }
  done
  return 1
}
