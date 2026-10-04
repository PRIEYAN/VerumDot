#!/usr/bin/env bash
# Fan control for hp-wmi laptops. See lib/domain/fan.sh for why the setting
# is three-way over a two-state device, and why `apply` has to be re-run at
# login and after every power-mode change.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/cli core/migrate domain/fan

migrate::run

cmd_get()    { fan::mode; echo; }
cmd_cycle()  { fan::cycle; }
cmd_apply()  { fan::apply; }
cmd_status() { fan::status; }

cmd_set() {
  cli::need 1 "set <auto|normal|max>" "$@"
  fan::set_mode "$1" || log::usage "set <auto|normal|max>"
}

declare -A COMMANDS=(
  [get]="cmd_get|print the current fan setting"
  [set]="cmd_set|<auto|normal|max>  change the fan setting"
  [cycle]="cmd_cycle|advance auto -> normal -> max -> auto"
  [apply]="cmd_apply|re-assert the saved setting against the current power mode"
  [status]="cmd_status|print setting, power mode, pwm value and live RPM"
)

cli::dispatch "${1:-status}" "${@:2}"
