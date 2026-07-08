#!/usr/bin/env bash
# Idle-inhibit toggle for eww (waybar's idle_inhibitor is a built-in GTK
# module with no CLI equivalent, so this drives a systemd-inhibit lock
# instead). State is tracked via a pidfile holding the inhibitor's PID.

pidfile="/tmp/eww-idle-inhibitor.pid"

is_active() {
  [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null
}

if [ "$1" = "toggle" ]; then
  if is_active; then
    kill "$(cat "$pidfile")" 2>/dev/null
    rm -f "$pidfile"
  else
    setsid systemd-inhibit --what=idle:sleep --who="eww" --why="User requested stay-awake" sleep infinity &
    echo $! > "$pidfile"
  fi
  exit 0
fi

if is_active; then
  # tea/coffee cup = staying awake
  printf '{"icon":"","tooltip":"Staying awake — click to allow sleep","class":"activated"}\n'
else
  # zzz = normal (will sleep when idle)
  printf '{"icon":"󰒲","tooltip":"Normal — click to keep the PC awake","class":"deactivated"}\n'
fi
