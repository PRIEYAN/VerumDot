#!/usr/bin/env bash
# Low-battery warnings, fired once per threshold while discharging and
# re-armed once the charge climbs back or AC returns.
#
# The thresholds and their copy are data in lib/domain/battery.sh. The old
# version hardcoded two branches here and called a four-parameter notify
# helper with three arguments for the 15% case, so the critical warning ran
# `notify-send -u ""` and was rejected by the daemon — the more urgent of
# the two alerts was the one that did not appear.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use domain/battery

readonly POLL_SECONDS=30

battery::present || log::die -c 0 "no battery on this machine; nothing to watch"

trap 'exit 0' TERM INT

while :; do
  capacity=$(battery::capacity)
  if battery::charging; then
    battery::clear_warnings
  else
    battery::check_thresholds "$capacity"
    battery::reset_above "$capacity"
  fi
  sleep "$POLL_SECONDS"
done
