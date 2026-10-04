#!/usr/bin/env bash
# Shutdown splash: a full-screen flash, then power off.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/guard core/paths os/proc

readonly SPLASH_TEXT="${HYPR_SHUTDOWN_TEXT:-MOGGER}"
readonly SPLASH_SECONDS=1
readonly SPLASH_THEME="${HYPR_RUN_DIR}/shutdown-splash.rasi"

# Without rofi there is no splash, but the shutdown must still happen —
# never let the decoration block the action.
if guard::has rofi; then
  paths::ensure_dirs
  cat >"$SPLASH_THEME" <<'RASI'
* {
    background-color: black;
    text-color: red;
}
window {
    fullscreen: true;
    padding: 40% 0%;
}
textbox {
    font: "Impact 150";
    horizontal-align: 0.5;
    vertical-align: 0.5;
}
RASI
  rofi -e "$SPLASH_TEXT" -theme "$SPLASH_THEME" &
  splash=$!
  sleep "$SPLASH_SECONDS"
  kill "$splash" 2>/dev/null || true
fi

exec systemctl poweroff
