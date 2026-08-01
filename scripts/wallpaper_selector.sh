#!/usr/bin/env bash

# Run inline (blocking) so rofi attaches to the Wayland session.

# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
"${HYPR_SCRIPTS}/wallpaper-center.sh"
