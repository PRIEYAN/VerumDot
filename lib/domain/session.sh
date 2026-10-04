#!/usr/bin/env bash
# domain/session.sh — locking and screen power.
#
# Locking has two paths: logind's lock-session, which is what any other
# session tool will also trigger, and hyprlock directly as a fallback. Both
# were spelled out inline in three scripts, each with a slightly different
# `||` arrangement — and one of them backgrounded the fallback with `&` in a
# position that also backgrounded the loginctl call.

hypr::use core/guard core/paths os/proc os/hypr

session::locked() { pidof hyprlock >/dev/null 2>&1; }

# session::lock — lock via logind, falling back to hyprlock directly.
session::lock() {
  proc::quiet loginctl lock-session && return 0
  guard::has hyprlock || return 1
  setsid -f hyprlock -c "$HYPR_HYPRLOCK_CONF" >/dev/null 2>&1
}

# session::ensure_locked — lock only if nothing is locked already, so a
# lid-open that fires twice does not stack two lock surfaces.
session::ensure_locked() {
  session::locked && return 0
  session::lock
}
