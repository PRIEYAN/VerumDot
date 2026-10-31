#!/usr/bin/env bash
# Waybar launcher and supervisor.
#
# Replaces `exec-once = sh -c "sleep 1 && waybar"`, which failed two ways on a
# cold boot: the sleep was a blind guess at when the compositor would be ready,
# and nothing watched the process afterwards. A waybar that lost that race (or
# died once under load, which is what a low battery or a slow disk produces)
# stayed gone for the whole session, so the bar was simply missing until it was
# started by hand.
#
# Instead: wait for the Hyprland event socket to actually exist, then keep
# waybar alive. The restart budget is deliberate — a transient crash is worth
# retrying, but a broken config would otherwise spin forever, so repeated
# instant failures give up and leave a notification behind.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/guard core/log os/proc os/hypr ui/notify

readonly WAYBAR_LOCK=waybar-supervisor
# A run shorter than this counts as "failed to start" rather than "crashed
# later": it is the signal that retrying is pointless.
readonly WAYBAR_MIN_RUN=5
readonly WAYBAR_MAX_FAST_FAILS=5
readonly WAYBAR_RESTART_DELAY=1

guard::has waybar || { log::warn "waybar is not installed"; exit 0; }

# One supervisor per session. Without this, a `hyprctl reload` or a second
# exec-once would stack supervisors and each would fight to respawn the bar.
proc::lock "$WAYBAR_LOCK" || { log::info "waybar supervisor already running"; exit 0; }

# The compositor must be up before waybar can bind its layer surface.
hypr::wait_for_socket "$(hypr::event_socket)" 100 \
  || log::warn "Hyprland socket never appeared; starting waybar anyway"

fast_fails=0
while (( fast_fails < WAYBAR_MAX_FAST_FAILS )); do
  started=$SECONDS
  # Via run_unlocked: waybar and the module scripts it spawns must not inherit
  # the supervisor's lock fd, or killing the supervisor while the bar lives
  # would leave the lock held and block every later supervisor.
  proc::run_unlocked waybar >/dev/null 2>&1
  ran=$(( SECONDS - started ))

  if (( ran >= WAYBAR_MIN_RUN )); then
    # It worked for a while, so this is a crash rather than a bad config:
    # reset the budget so a long session is always allowed a fresh retry.
    fast_fails=0
    log::info "waybar exited after ${ran}s; restarting"
  else
    (( fast_fails++ ))
    log::warn "waybar died after ${ran}s (${fast_fails}/${WAYBAR_MAX_FAST_FAILS})"
  fi

  sleep "$WAYBAR_RESTART_DELAY"
done

log::warn "waybar failed ${WAYBAR_MAX_FAST_FAILS} times in a row; giving up"
notify::send -u critical -r waybar-supervisor "Waybar" \
  "Failed to start after ${WAYBAR_MAX_FAST_FAILS} attempts. Run waybar in a terminal to see why."
