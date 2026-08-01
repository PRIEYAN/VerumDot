#!/usr/bin/env bash
#
# Tiny helper: close an eww window. Pure shell.
#   eww-close.sh <window>


# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
eww -c "${HYPR_EWW}" close "$1" >/dev/null 2>&1
