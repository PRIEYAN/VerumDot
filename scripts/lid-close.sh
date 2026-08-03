#!/usr/bin/env bash
#
# Lid closed: lock the session and turn the panel off.
# Does NOT suspend/hibernate — logind HandleLidSwitch must be `ignore`
# (see apps/systemd/10-lid-lock.conf).

set -euo pipefail

# Lock first so hyprlock is ready before the panel blanks.
loginctl lock-session 2>/dev/null || hyprlock &

# Brief settle so the lock surface maps, then blank the display.
sleep 0.15
hyprctl dispatch dpms off >/dev/null 2>&1 || true
