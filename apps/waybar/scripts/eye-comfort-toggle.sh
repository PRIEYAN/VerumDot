#!/usr/bin/env bash
# Eye Comfort control, shared by waybar and the control centre.
# The behaviour lives in lib/domain/eyecomfort.sh.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/cli domain/eyecomfort

cmd_toggle() { eyecomfort::toggle; }
cmd_status() { eyecomfort::status_json; }

cmd_apply() {
  cli::need 2 "apply <on|off> <0-100>" "$@"
  case $1 in on|off) ;; *) log::usage "apply <on|off> <0-100>" ;; esac
  eyecomfort::apply "$1" "$2"
}

declare -A COMMANDS=(
  [toggle]="cmd_toggle|turn the warm tint on or off (the default)"
  [status]="cmd_status|print {enabled, intensity, available} as JSON"
  [apply]="cmd_apply|<on|off> <0-100>  set state and intensity together"
)

cli::dispatch "${1:-toggle}" "${@:2}"
