#!/usr/bin/env bash
#
# Power action backend for the eww panel. Pure shell.
# Closes the panel first, then runs the session action.


# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/_paths.sh"
EWW="eww -c "${HYPR_EWW}""
HYPR_CONFIG="${HYPR_APPS}/hyprlock/hyprlock.conf"
SHUTDOWN_SCRIPT="${HYPR_SCRIPTS}/mogger_shutdown.sh"

$EWW close power >/dev/null 2>&1

case "$1" in
  lock)     setsid -f hyprlock -c "$HYPR_CONFIG" >/dev/null 2>&1 ;;
  suspend)  systemctl suspend ;;
  logout)   hyprctl dispatch exit ;;
  reboot)   systemctl reboot ;;
  shutdown) setsid -f "$SHUTDOWN_SCRIPT" >/dev/null 2>&1 ;;
esac
