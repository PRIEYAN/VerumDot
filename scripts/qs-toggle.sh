#!/usr/bin/env bash
#
# Toggle a quickshell surface over IPC, starting its daemon first if it is not
# up yet. Exits non-zero when quickshell is unavailable so callers can fall
# back to their old rofi popup.
#
#   qs-toggle.sh <config dir under apps/quickshell> <IpcHandler target>

# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_paths.sh"

name=${1:?usage: qs-toggle.sh <config> <ipc target>}
target=${2:?usage: qs-toggle.sh <config> <ipc target>}
cfg="${HYPR_APPS}/quickshell/${name}"

command -v qs >/dev/null 2>&1 || exit 1
[ -f "${cfg}/shell.qml" ] || exit 1

# Normal path: the daemon is already running, so this is just a toggle.
qs -p "$cfg" ipc call "$target" toggle >/dev/null 2>&1 && exit 0

# No daemon yet (first call after install, before the exec-once has run).
setsid -f qs -p "$cfg" -n >/dev/null 2>&1
n=0
while [ "$n" -lt 20 ]; do
  sleep 0.25
  qs -p "$cfg" ipc call "$target" open >/dev/null 2>&1 && exit 0
  n=$((n + 1))
done
exit 1
