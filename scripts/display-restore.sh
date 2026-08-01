#!/usr/bin/env bash
#
# Bring the internal panel back after a lid-open or a resume.
#
# `hyprctl dispatch dpms on` is not sufficient on its own. dpms only toggles
# the power state of an output that is still *enabled*; when the lid shuts,
# the output can end up disabled outright, and a disabled output cannot be
# dpms'd back. The monitor line has to be re-declared first or the panel
# stays black and the session reads as hung — at which point the natural
# reaction is to press the power button, which (with logind's default
# HandlePowerKey=poweroff) hard-kills the machine and loses the session.
#
# Everything here is idempotent: re-declaring a monitor that is already
# correct is a no-op, so this is safe to fire on every lid-open and resume.


# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
MONITOR_LINE="eDP-1,preferred,auto,1.0"

# DRM can need a moment to settle coming out of suspend, so re-assert a few
# times rather than firing once into a device that is not ready yet.
for _ in 1 2 3 4 5; do
    hyprctl keyword monitor "$MONITOR_LINE" >/dev/null 2>&1
    hyprctl dispatch dpms on                >/dev/null 2>&1

    # dpmsStatus 1 = panel powered. Stop as soon as it reports back.
    if hyprctl -j monitors 2>/dev/null | grep -q '"dpmsStatus": *true'; then
        exit 0
    fi
    sleep 0.4
done

# Last-ditch: even if the status probe never confirmed, leave the panel
# commanded on rather than exiting with it dark.
hyprctl dispatch dpms on >/dev/null 2>&1
exit 0
