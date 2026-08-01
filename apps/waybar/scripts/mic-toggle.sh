#!/usr/bin/env bash

# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../scripts" && pwd)/_paths.sh"
if command -v pamixer >/dev/null 2>&1; then
  pamixer --default-source -t 2>/dev/null || pamixer -t
else
  rofi -e 'pamixer not installed'
fi
