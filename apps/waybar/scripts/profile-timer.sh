#!/usr/bin/env bash
# Persisted stopwatch behind the profile dropdown.
#
# On-disk shape is unchanged:
#   {"running": bool, "elapsed": float, "started_at": float|null}
#
# The elapsed total is only folded in when the timer stops; while it runs,
# the in-flight segment is added at read time. That way a crash loses at
# most the current segment rather than corrupting the total.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/cli os/jsonstore

readonly STORE=profile-timer
readonly EMPTY='{"running":false,"elapsed":0.0,"started_at":null}'

now() { date +%s.%N; }

# Merged over the default so a partial document still has every key.
load() { jsonstore::load "$STORE" "$EMPTY" | jq -c --argjson d "$EMPTY" '$d * .'; }

cmd_toggle() {
  local state; state=$(load)
  if [[ $(jq -r '.running' <<<"$state") == true ]]; then
    state=$(jq -c --argjson n "$(now)" \
      '.elapsed = (.elapsed + ($n - (.started_at // $n))) | .running = false | .started_at = null' \
      <<<"$state")
  else
    state=$(jq -c --argjson n "$(now)" '.running = true | .started_at = $n' <<<"$state")
  fi
  jsonstore::save "$STORE" "$state"
  cmd_status
}

cmd_reset() {
  jsonstore::save "$STORE" "$EMPTY"
  cmd_status
}

cmd_status() {
  local elapsed running
  read -r elapsed running < <(load | jq -r --argjson n "$(now)" \
    '((if .running then .elapsed + ($n - (.started_at // $n)) else .elapsed end) | floor | tostring)
     + " " + (.running | tostring)')
  printf '%02d:%02d:%02d %s\n' \
    $(( elapsed / 3600 )) $(( (elapsed % 3600) / 60 )) $(( elapsed % 60 )) \
    "$([[ $running == true ]] && echo Pause || echo Start)"
}

declare -A COMMANDS=(
  [status]="cmd_status|print elapsed time and the next action (the default)"
  [toggle]="cmd_toggle|start or pause the stopwatch"
  [reset]="cmd_reset|reset to 00:00:00"
)

cli::dispatch "${1:-status}" "${@:2}"
