#!/usr/bin/env bash
# Bring the internal panel back after a lid-open or a resume.
#
# `hyprctl dispatch dpms on` is not sufficient on its own: dpms only toggles
# the power state of an output that is still *enabled*, and when the lid
# shuts the output can end up disabled outright. A disabled output cannot be
# dpms'd back, so the monitor line has to be re-declared first — otherwise
# the panel stays black and the session reads as hung, at which point the
# natural reaction is to press the power button, which with logind's default
# HandlePowerKey=poweroff hard-kills the machine and loses the session.
#
# Everything here is idempotent: re-declaring a monitor that is already
# correct is a no-op, so this is safe to fire on every lid-open and resume.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/paths os/hypr os/proc domain/session

readonly MONITOR_LINE="${HYPR_MONITOR_LINE:-eDP-1,preferred,auto,1.0}"
readonly RESTORE_ATTEMPTS=5
readonly RESTORE_DELAY=0.4

# DRM can need a moment to settle coming out of suspend, so re-assert a few
# times rather than firing once into a device that is not ready yet.
for (( attempt = 0; attempt < RESTORE_ATTEMPTS; attempt++ )); do
  hypr::keyword monitor "$MONITOR_LINE"
  hypr::dispatch dpms on

  if hypr::panel_powered; then
    session::ensure_locked
    exit 0
  fi
  sleep "$RESTORE_DELAY"
done

# Last-ditch: even if the status probe never confirmed, leave the panel
# commanded on rather than exiting with it dark.
hypr::dispatch dpms on
session::ensure_locked
exit 0
