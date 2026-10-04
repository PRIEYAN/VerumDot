#!/usr/bin/env bash
# ui/quickshell.sh — toggling quickshell surfaces over IPC.
#
# Each surface (launcher, spotify, controlcenter, keybinds) runs as a daemon
# started by an exec-once in hypr.conf. A click is then just an IPC call
# against the live surface, which is what lets these panels redraw in place
# — the rofi popups they replaced could only update by exiting and
# relaunching, which is what made them flicker and dismiss themselves.

hypr::use core/guard core/log core/paths os/proc

readonly QS_START_ATTEMPTS=20
readonly QS_START_DELAY=0.25

quickshell::available() { guard::has qs; }

quickshell::config_dir() { paths::quickshell "$1"; }

quickshell::installed() { [[ -f "$(quickshell::config_dir "$1")/shell.qml" ]]; }

# quickshell::call <surface> <target> <method> — one IPC call, no retry.
quickshell::call() {
  local surface=$1 target=$2 method=$3
  proc::quiet qs -p "$(quickshell::config_dir "$surface")" ipc call "$target" "$method"
}

# quickshell::read <surface> <target> <method> — an IPC call whose reply we
# want (the stay-awake state, for instance).
quickshell::read() {
  local surface=$1 target=$2 method=$3
  proc::capture qs -p "$(quickshell::config_dir "$surface")" ipc call "$target" "$method"
}

# quickshell::start <surface> — launch the daemon detached and wait for it
# to answer IPC. Used on the first call after an install, before the
# exec-once has run.
quickshell::start() {
  local surface=$1 target=$2 method=${3:-open} attempt
  proc::detach qs -p "$(quickshell::config_dir "$surface")" -n
  for (( attempt = 0; attempt < QS_START_ATTEMPTS; attempt++ )); do
    sleep "$QS_START_DELAY"
    quickshell::call "$surface" "$target" "$method" && return 0
  done
  return 1
}

# quickshell::toggle <surface> <target> — the normal path: toggle the live
# surface, starting its daemon first if it is not up yet.
#
# Returns non-zero when quickshell is unavailable entirely, so callers can
# fall back (app-launcher drops to `rofi -show drun`).
quickshell::toggle() {
  local surface=$1 target=$2
  quickshell::available  || return 1
  quickshell::installed "$surface" || return 1
  quickshell::call "$surface" "$target" toggle && return 0
  quickshell::start "$surface" "$target" open
}
