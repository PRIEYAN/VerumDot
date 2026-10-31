#!/usr/bin/env bash
# Boot splash — launches the quickshell splash surface and guarantees it dies.
#
# The surface hides itself after one second (see apps/quickshell/splash), but
# the process outlives that by ~3.5s: tearing down the QtMultimedia ffmpeg
# decoder blocks on exit. That tail is invisible, yet it keeps a decoder thread
# and a GPU context alive through exactly the part of boot the splash exists to
# cover, so the deadline is enforced from outside instead of trusted to QML.
#
# Runs in the foreground; hyprland.conf backgrounds it with its own exec-once.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/guard core/log ui/quickshell

readonly SPLASH_SURFACE=splash
# The surface's own budget is 1s; allow a little slack for qs startup before
# pulling the plug, then escalate if it ignores the TERM.
readonly SPLASH_DEADLINE=1.6

quickshell::available || { log::warn "quickshell missing, skipping splash"; exit 0; }
quickshell::installed "$SPLASH_SURFACE" || { log::warn "splash surface missing"; exit 0; }

# Being killed on the deadline is the normal path, not a failure, so the
# timeout's 124/137 is swallowed rather than reported to the session log.
timeout --kill-after=0.5 "$SPLASH_DEADLINE" \
  qs -p "$(quickshell::config_dir "$SPLASH_SURFACE")" >/dev/null 2>&1
exit 0
