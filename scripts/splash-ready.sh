#!/usr/bin/env bash
# Readiness probe for the boot splash: exit 0 once the desktop is painted.
#
# "Painted" means the two things whose absence is actually visible when the
# splash lifts — the wallpaper and the bar. hypridle, the applets and the
# quickshell daemons are deliberately not checked: nothing is on screen for
# them until they are clicked, so waiting on them would only delay the reveal.
#
# Called repeatedly by apps/quickshell/splash; must stay cheap and silent.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use os/hypr

# hyprpaper answering IPC is the wallpaper's own readiness signal — the same
# socket wallpaper.sh waits on before pushing an image to it.
[[ -S "$(hypr::hyprpaper_socket)" ]] || exit 1

# waybar is checked by process rather than by its layer surface: hyprctl
# exposes no layer list, and the gap between the process existing and the bar
# being drawn is well inside the splash's own fade.
pgrep -x waybar >/dev/null 2>&1 || exit 1

exit 0
