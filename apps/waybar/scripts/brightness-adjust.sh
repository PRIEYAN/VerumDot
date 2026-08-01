#!/usr/bin/env bash

# Redirect to our unified hardware + software super-brightness script

# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../scripts" && pwd)/_paths.sh"
case "$1" in
  up) "${HYPR_SCRIPTS}/brightness_control.sh" up;;
  down) "${HYPR_SCRIPTS}/brightness_control.sh" down;;
esac
