#!/usr/bin/env bash

# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
set -euo pipefail

# Lock after 5 minutes, turn screen off after 10 minutes
exec hypridle --lock 5m --off 10m
