#!/usr/bin/env bash
#
# App launcher. Opens the quickshell launcher (apps/quickshell/launcher), and
# falls back to `rofi -show drun` if quickshell is missing.

# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"

"${HYPR_SCRIPTS}/qs-toggle.sh" launcher launcher && exit 0

exec rofi -show drun -config "${HYPR_ROFI}/config.rasi"
