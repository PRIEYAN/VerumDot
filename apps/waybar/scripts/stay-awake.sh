#!/usr/bin/env bash
# Idle-inhibitor module. Both the bar button and the control centre drive the
# control centre's single Wayland idle inhibitor, so the two cannot disagree
# about whether sleep is inhibited.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/cli ui/waybar ui/quickshell

readonly SURFACE=controlcenter
readonly TARGET=controlcenter

cmd_toggle() {
  quickshell::call "$SURFACE" "$TARGET" toggleStayAwake && return 0
  # The daemon is not up yet — start it, then retry the toggle.
  quickshell::start "$SURFACE" "$TARGET" toggleStayAwake
}

cmd_status() {
  case "$(quickshell::read "$SURFACE" "$TARGET" isStayAwake)" in
    true)  waybar::emit '󰅶' 'Staying awake — click to allow sleep' activated ;;
    false) waybar::emit '󰒲' 'Normal — click to keep the PC awake' deactivated ;;
    *)     waybar::emit '󰒲' 'Stay Awake unavailable — click to start Control Centre' unavailable ;;
  esac
}

declare -A COMMANDS=(
  [status]="cmd_status|emit the waybar module JSON (the default)"
  [toggle]="cmd_toggle|toggle the idle inhibitor"
)

cli::dispatch "${1:-status}" "${@:2}"
