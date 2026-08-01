#!/usr/bin/env bash


# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"
if [ "$1" = "menu" ]; then
  eww -c "${HYPR_EWW}" open --toggle power
  exit 0
fi

printf '{"text":"⏻","tooltip":"Power"}\n'
