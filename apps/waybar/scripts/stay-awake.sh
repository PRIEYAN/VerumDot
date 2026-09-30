#!/usr/bin/env bash
# Both controls use the control centre's single Wayland idle inhibitor.
cfg="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../quickshell/controlcenter" && pwd)"
if [ "${1:-status}" = toggle ]; then
  if ! qs -p "$cfg" ipc call controlcenter toggleStayAwake >/dev/null 2>&1; then
    setsid -f qs -p "$cfg" -n >/dev/null 2>&1
    for ((attempt=0; attempt<20; attempt++)); do
      sleep 0.1
      qs -p "$cfg" ipc call controlcenter toggleStayAwake >/dev/null 2>&1 && exit 0
    done
    exit 1
  fi
  exit 0
fi
state=$(qs -p "$cfg" ipc call controlcenter isStayAwake 2>/dev/null)
case "$state" in
  true) printf '{"text":"󰅶","class":"activated","tooltip":"Staying awake — click to allow sleep"}\n' ;;
  false) printf '{"text":"󰒲","class":"deactivated","tooltip":"Normal — click to keep the PC awake"}\n' ;;
  *) printf '{"text":"󰒲","class":"unavailable","tooltip":"Stay Awake unavailable — click to start Control Centre"}\n' ;;
esac
