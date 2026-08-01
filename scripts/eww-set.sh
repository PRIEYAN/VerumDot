#!/usr/bin/env bash
#
# Tiny helper: set an eww variable. Keeps onclick strings in the .yuck
# short and free of nested quotes. Pure shell.
#   eww-set.sh <var> <value>


# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
eww -c "${HYPR_EWW}" update "$1=$2" >/dev/null 2>&1
