#!/usr/bin/env bash
#
# Volume data backend for the eww panel. Pure shell.
# Emits {volume, muted} as JSON. Falls back from pamixer to wpctl.

if command -v pamixer >/dev/null 2>&1; then
  vol=$(pamixer --get-volume 2>/dev/null)
  if pamixer --get-mute 2>/dev/null | grep -Eq 'true|1'; then muted=true; else muted=false; fi
elif command -v wpctl >/dev/null 2>&1; then
  raw=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
  vol=$(printf '%s' "$raw" | awk '{printf "%d", $2 * 100}')
  if printf '%s' "$raw" | grep -q MUTED; then muted=true; else muted=false; fi
fi
[ -z "$vol" ] && vol=0
[ -z "$muted" ] && muted=false

printf '{"volume":%s,"muted":%s}\n' "$vol" "$muted"
