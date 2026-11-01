#!/usr/bin/env bash
# Lid closed: lock the session and blank the panel.
#
# Deliberately does not suspend or hibernate — logind's HandleLidSwitch must
# be `ignore` for this to be the only handler (see
# apps/systemd/10-lid-lock.conf).

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use os/hypr domain/session

# Pause every MPRIS player, including supported browsers, before the lid
# blanks the screen. A missing or inactive player must not block locking.
if command -v playerctl >/dev/null 2>&1; then
  playerctl --all-players pause >/dev/null 2>&1 || true
fi

# Lock first so the lock surface is up before the panel goes dark; a brief
# settle lets it map before blanking.
session::lock
sleep 0.15
hypr::dispatch dpms off
