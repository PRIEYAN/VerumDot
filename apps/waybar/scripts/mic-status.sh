#!/usr/bin/env bash

# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../scripts" && pwd)/_paths.sh"
if command -v pamixer >/dev/null 2>&1; then
  mute=$(pamixer --default-source --get-mute 2>/dev/null || pamixer --get-mute 2>/dev/null)
  icon=''
  [ "$mute" = "true" ] && icon=''
  echo '{"text":"'$icon'","tooltip":"Click to toggle microphone"}'
else
  echo '{"text":"","tooltip":"pamixer missing"}'
fi
