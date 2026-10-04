#!/usr/bin/env bash
# Session actions for the eww power panel. Closes the panel first, so the
# overlay is gone before the action takes effect.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/cli core/paths os/proc ui/eww domain/power

eww::close power

cmd_lock()     { power::lock; }
cmd_logout()   { power::logout; }
cmd_reboot()   { power::reboot; }
cmd_suspend()  { exec systemctl suspend; }
cmd_shutdown() { proc::detach "$(paths::script mogger-shutdown.sh)"; }

declare -A COMMANDS=(
  [lock]="cmd_lock|lock the session"
  [logout]="cmd_logout|exit the compositor"
  [reboot]="cmd_reboot|restart the machine"
  [suspend]="cmd_suspend|suspend to RAM"
  [shutdown]="cmd_shutdown|power off, with the splash"
)

cli::dispatch "${1:-}" "${@:2}"
