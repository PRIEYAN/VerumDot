#!/usr/bin/env bash
# Optional login animation. QML owns the visible timing; an external watchdog
# separately bounds cold initialization and stuck media cleanup. Failures are
# logged and never prevent the desktop from starting.
#
# Run this launcher, not the QML directly, to retain duplicate protection and
# the process deadline. Hyprland starts it through exec-once.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/guard core/log ui/quickshell

readonly SPLASH_SURFACE=splash
# QML stays hidden during initialization, then unmaps within its 850ms budget.
# Cold Qt/GPU initialization can take ~2s, so this separately bounds startup
# plus teardown. It is not the visible animation duration;
# TERM is escalated after 500ms if Qt/FFmpeg is unresponsive.
readonly SPLASH_DEADLINE=4

quickshell::available || { log::warn "quickshell missing, skipping splash"; exit 0; }
quickshell::installed "$SPLASH_SURFACE" || { log::warn "splash surface missing"; exit 0; }
[[ -s "$HYPR_HOME/assets/splash.mp4" ]] || { log::warn "splash video missing, skipping splash"; exit 0; }

# Concurrent startup/preview requests must not stack fullscreen overlays.
# Scope the lock to this compositor session, not other sessions of the user.
session=${HYPRLAND_INSTANCE_SIGNATURE:-${WAYLAND_DISPLAY:-default}}
session=${session//[^a-zA-Z0-9_-]/_}
proc::lock "splash-$session" || exit 0
mkdir -p -- "$HYPR_CACHE_DIR" || exit 0
readonly SPLASH_LOG="$HYPR_CACHE_DIR/splash.log"

# Keep QML diagnostics for missing modules/media errors. Only our child process
# group is timed out; other Quickshell panels must continue running.
# The splash needs no desktop portal; waiting for portal activation at login
# can consume its entire budget before Qt even creates the first window.
# Decode this short clip on the CPU: probing NVIDIA/VAAPI devices can take
# longer than the animation itself on hybrid-GPU laptops. This is scoped to
# this process; rendering and other applications keep their normal GPU setup.
proc::run_unlocked env QT_NO_XDG_DESKTOP_PORTAL=1 QT_FFMPEG_DECODING_HW_DEVICE_TYPES=, \
  timeout --kill-after=0.5 "$SPLASH_DEADLINE" \
  qs -p "$(quickshell::config_dir "$SPLASH_SURFACE")" -n >"$SPLASH_LOG" 2>&1
rc=$?
case $rc in
  0) ;;
  124|137) printf 'splash: external deadline reached; process cleaned up\n' >>"$SPLASH_LOG" ;;
  *) printf 'splash: exited with status %s (login continues)\n' "$rc" >>"$SPLASH_LOG" ;;
esac
# The splash is cosmetic: failure must never fail the login startup command.
exit 0
