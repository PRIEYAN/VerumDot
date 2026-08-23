#!/usr/bin/env bash
#
# Eye comfort mode: toggles a 3000K warm tint via hyprsunset.
# Bound to a click on the waybar brightness module.
#
# Why not redshift: redshift 1.12 has no Wayland backend. Its DRM fallback
# writes the panel gamma ramp directly and exits 0, but Hyprland owns the
# atomic display pipeline and overwrites the ramp on its next commit -- so
# the tint never reaches the screen and nothing reports an error.
#
# hyprsunset applies the temperature through the compositor itself, so it
# sticks. This build (v0.4.0) has no `hyprctl hyprsunset` IPC, so the toggle
# manages the daemon: running with -t means warm, not running means normal.

# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../scripts" && pwd)/_paths.sh"

TEMP=3000

notify() {
  command -v notify-send >/dev/null 2>&1 \
    && notify-send -a "Eye Comfort" \
       -h string:x-canonical-private-synchronous:eye-comfort \
       "$1" "$2" 2>/dev/null || true
}

if ! command -v hyprsunset >/dev/null 2>&1; then
  notify "Eye Comfort" "hyprsunset is not installed"
  exit 1
fi

# A bare `hyprsunset` with no -t sits at its 6000K default doing nothing, so
# treat "warm" as specifically a process carrying a -t argument.
# The ^ anchor matters: an unanchored pattern also matches the invoking shell.
warm_pid=$(pgrep -af '^hyprsunset .*-t' | awk 'NR==1{print $1}')

if [ -n "$warm_pid" ]; then
  pkill -x hyprsunset 2>/dev/null
  notify "Eye Comfort Off" "Normal color temperature"
else
  # Clear any stray neutral daemon first, so only one instance owns the gamma.
  pkill -x hyprsunset 2>/dev/null
  sleep 0.3
  setsid -f hyprsunset -t "$TEMP" >/dev/null 2>&1
  notify "Eye Comfort" "Warm tint (${TEMP}K)"
fi

# Repaint the module so any state it shows stays in sync.
pkill -RTMIN+1 waybar 2>/dev/null || true
