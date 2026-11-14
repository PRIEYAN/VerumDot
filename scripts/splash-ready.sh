#!/usr/bin/env bash
# Readiness probe for the boot splash: exit 0 once the desktop layers are mapped.
#
# "Ready" means the two things whose absence is actually visible when the
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

# Query mapped layers in this compositor instance. A process existing (or a
# wallpaper socket accepting connections) does not mean a surface is visible.
# Require both desktop layers on every output reported by Hyprland. The query
# is bounded so a stuck IPC socket cannot accumulate readiness processes.
guard::has hyprctl jq timeout || exit 1
[[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || exit 1
timeout --kill-after=0.05 0.15 hyprctl -j layers 2>/dev/null | jq -e '
  type == "object" and length > 0 and all(.[];
    [.levels[][]? | select(.w > 0 and .h > 0 and (.alpha // 1) > 0) | .namespace] as $names
    | ($names | index("hyprpaper")) != null and ($names | index("waybar")) != null
  )
' >/dev/null 2>&1
