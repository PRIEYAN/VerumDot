#!/usr/bin/env bash
# os/proc.sh — running other programs, and not running two of ourselves.

hypr::use core/log core/guard core/paths

# proc::quiet <cmd>... — run, discarding both streams, returning the status.
# The single most repeated idiom in the old scripts (`>/dev/null 2>&1`), where
# forgetting the `2>&1` half leaked daemon chatter into a waybar module.
proc::quiet() { "$@" >/dev/null 2>&1; }

# proc::capture <cmd>... — stdout on success, empty string on failure.
# Never leaks the command's stderr into our own output.
proc::capture() {
  local out
  out=$("$@" 2>/dev/null) || return 1
  printf '%s' "$out"
}

# proc::capture_or <default> <cmd>... — stdout, or the default when the
# command fails or prints nothing. Collapses the
# `x=$(cmd 2>/dev/null || echo fallback)` pattern, which silently kept an
# empty string whenever the command succeeded but had nothing to say.
proc::capture_or() {
  local fallback=$1 out; shift
  out=$(proc::capture "$@") || out=""
  printf '%s' "${out:-$fallback}"
}

# proc::detach <cmd>... — start a program that must outlive this script
# (a lock screen, a settings editor, a wallpaper setter). setsid detaches it
# from our process group so it survives our exit and Hyprland's cleanup.
proc::detach() {
  setsid -f -- "$@" >/dev/null 2>&1
}

# proc::first_available <cmd-with-args>... — run each candidate in turn,
# stopping at the first that succeeds. Models the
# `wpctl ... || pamixer ... || pactl ...` fallback chains as data.
# Each candidate is a single string, split on whitespace.
proc::first_available() {
  local candidate parts
  for candidate in "$@"; do
    read -r -a parts <<<"$candidate"
    guard::has "${parts[0]}" || continue
    proc::quiet "${parts[@]}" && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# Single-instance locking
# ---------------------------------------------------------------------------
# proc::lock <name> — take an exclusive, non-blocking lock for the rest of
# this process's life. Returns 1 if another instance already holds it.
#
# This replaces the `pgrep -f "rofi.*foo.rasi"` tests the popups used, which
# matched on a command line and so could be defeated by an unrelated process
# (or by the grep seeing itself).
proc::lock() {
  local name=$1 fd
  paths::ensure_dirs
  exec {fd}>"${HYPR_RUN_DIR}/${name}.lock" || return 1
  flock -n "$fd" || return 1
  # Deliberately not closed: the kernel releases it when we exit, which is
  # exactly the lifetime we want and is robust to being killed.
  return 0
}

# proc::held <name> — true if someone currently holds the named lock.
proc::held() {
  local name=$1 fd
  exec {fd}>>"${HYPR_RUN_DIR}/${name}.lock" 2>/dev/null || return 1
  if flock -n "$fd"; then
    flock -u "$fd"; exec {fd}>&-
    return 1
  fi
  exec {fd}>&-
  return 0
}

# ---------------------------------------------------------------------------
# Toggleable popups
# ---------------------------------------------------------------------------
# proc::toggle_guard <name> — the shared open/close semantics of every popup
# bound to a bar button: the first invocation opens, a second while it is
# still up closes it.
#
# Returns 0 ("carry on and show the popup") after taking the lock, or 1
# ("we just dismissed the running one") after killing it.
proc::toggle_guard() {
  local name=$1
  if proc::held "$name"; then
    proc::kill_group "$name"
    return 1
  fi
  proc::lock "$name"
}

# proc::kill_group <name> — terminate the process that registered under this
# name via proc::register. Falls back to doing nothing, which is correct:
# the lock will be released when that process dies on its own.
proc::kill_group() {
  local pidfile="${HYPR_RUN_DIR}/${1}.pid" pid
  [[ -r $pidfile ]] || return 0
  pid=$(<"$pidfile")
  [[ $pid =~ ^[0-9]+$ ]] || return 0
  kill -TERM "$pid" 2>/dev/null || true
  rm -f -- "$pidfile"
}

# proc::register <name> [pid] — record a pid so proc::kill_group can find it.
proc::register() {
  paths::ensure_dirs
  printf '%s' "${2:-$$}" >"${HYPR_RUN_DIR}/${1}.pid"
}
