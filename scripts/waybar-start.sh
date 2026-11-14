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

# Resolve the socket on every attempt: resolving once before it exists gives
# an empty path, which can never become ready no matter how long we wait.
socket=""
for (( attempt = 0; attempt < 100; attempt++ )); do
  socket=$(hypr::event_socket)
  [[ -S "$socket" ]] && break
  sleep 0.1
done
[[ -S "$socket" ]] || { log::warn "Hyprland socket never appeared; skipping waybar"; exit 1; }
mkdir -p -- "$HYPR_CACHE_DIR" || exit 1
readonly WAYBAR_LOG="$HYPR_CACHE_DIR/waybar-start.log"
: >"$WAYBAR_LOG"
child=""
# Called by the EXIT trap.
# shellcheck disable=SC2329
cleanup() {
  [[ -z "$child" ]] || kill "$child" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 0' INT TERM HUP

fast_fails=0
while (( fast_fails < WAYBAR_MAX_FAST_FAILS )); do
  started=$SECONDS
  # Close the supervisor lock in the child, then exec so $child is Waybar
  # itself. Terminating the supervisor must stop only its own bar process.
  (
    exec {PROC_LOCK_FD}>&-
    exec waybar -c "$HYPR_WAYBAR/config.jsonc" -s "$HYPR_WAYBAR/style.css"
  ) >>"$WAYBAR_LOG" 2>&1 &
  child=$!
  wait "$child"
  child=""
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

  (( fast_fails < WAYBAR_MAX_FAST_FAILS )) && sleep "$WAYBAR_RESTART_DELAY"
done

log::warn "waybar failed ${WAYBAR_MAX_FAST_FAILS} times in a row; giving up"
notify::send -u critical -r waybar-supervisor "Waybar" \
  "Failed to start after ${WAYBAR_MAX_FAST_FAILS} attempts. See $WAYBAR_LOG."
exit 1
