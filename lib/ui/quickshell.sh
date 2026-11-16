#!/usr/bin/env bash
# ui/quickshell.sh — toggling quickshell surfaces over IPC.
#
# Each surface (launcher, spotify, controlcenter, keybinds) runs as a daemon
# started from config/autostart.lua. A click is then just an IPC call
# against the live surface, which is what lets these panels redraw in place
# — the rofi popups they replaced could only update by exiting and
# relaunching, which is what made them flicker and dismiss themselves.

hypr::use core/guard core/log core/paths os/proc

readonly QS_START_ATTEMPTS=20
readonly QS_START_DELAY=0.25

quickshell::available() { guard::has qs; }

quickshell::config_dir() { paths::quickshell "$1"; }

quickshell::installed() { [[ -f "$(quickshell::config_dir "$1")/shell.qml" ]]; }

# quickshell::call <surface> <target> <method> [args...] — one IPC call, no
# retry. Extra arguments go to the method (showPage wifi, for instance).
quickshell::call() {
  local surface=$1 target=$2 method=$3
  proc::quiet qs -p "$(quickshell::config_dir "$surface")" ipc call "$target" "$method" "${@:4}"
}

# quickshell::read <surface> <target> <method> — an IPC call whose reply we
# want (the stay-awake state, for instance).
quickshell::read() {
  local surface=$1 target=$2 method=$3
  proc::capture qs -p "$(quickshell::config_dir "$surface")" ipc call "$target" "$method" "${@:4}"
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

# quickshell::toggle_page <surface> <target> <page> — open a surface straight
# to one of its pages (the control center's "wifi" or "bluetooth"). A second
# click on the same icon closes it again, like the surface's own toggle; a
# click while it shows a different page just switches pages.
#
# Returns non-zero when quickshell is unavailable, so callers can fall back
# to their rofi dropdown.
quickshell::toggle_page() {
  local surface=$1 target=$2 page=$3 open current
  quickshell::available  || return 1
  quickshell::installed "$surface" || return 1
  if open=$(quickshell::read "$surface" "$target" isOpen); then
    current=$(quickshell::read "$surface" "$target" currentPage)
    if [[ $open == true && $current == "$page" ]]; then
      quickshell::call "$surface" "$target" close
    else
      quickshell::call "$surface" "$target" showPage "$page"
    fi
    return
  fi
  quickshell::start "$surface" "$target" open || return 1
  quickshell::call "$surface" "$target" showPage "$page"
}
