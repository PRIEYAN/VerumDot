#!/usr/bin/env bash
# Idle-inhibit ("stay awake") toggle for eww. When active, the PC must NOT
# lock, blank, or suspend while untouched. Two independent things can idle us,
# so we block both:
#
#   1. hypridle — fires the lock (loginctl lock-session) and dpms-off from its
#      own timers. It listens to the Wayland idle protocol and only honours
#      `systemd-inhibit --what=idle` on newer builds (and even then the value
#      must be exactly `idle`, not `idle:sleep`). To work on ANY version we
#      PAUSE hypridle by stopping the process, and restart it when the user
#      allows sleep again. This is what actually stopped the lock screen.
#   2. logind — could idle-suspend / handle sleep. Covered by a systemd-inhibit
#      block lock held open for as long as we're staying awake.
#
# State is tracked by a pidfile holding the systemd-inhibit PID.

pidfile="${XDG_RUNTIME_DIR:-/tmp}/eww-idle-inhibitor.pid"

# Glyphs via UTF-8 byte escapes so the PUA characters survive encoding.
#   coffee  U+F0176 (staying awake)
#   sleep   U+F04B2 (normal / will sleep)
G_CUP=$(printf '\xf3\xb0\x85\xb6')
G_ZZZ=$(printf '\xf3\xb0\x92\xb2')

is_active() {
  [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile" 2>/dev/null)" 2>/dev/null
}

hypridle_running() { pgrep -x hypridle >/dev/null 2>&1; }

# Restart hypridle (reads its default config: ~/.config/hypr/hypridle.conf,
# which symlinks to apps/hypridle/hypridle.conf). Only if not already up.
start_hypridle() { hypridle_running || setsid -f hypridle >/dev/null 2>&1; }

# Pause hypridle so it cannot lock/blank while we stay awake.
stop_hypridle() { pkill -x hypridle 2>/dev/null; return 0; }

status_json() {
  if is_active; then
    printf '{"icon":"%s","tooltip":"Staying awake — click to allow sleep","class":"activated"}\n' "$G_CUP"
  else
    printf '{"icon":"%s","tooltip":"Normal — click to keep the PC awake","class":"deactivated"}\n' "$G_ZZZ"
  fi
}

if [ "$1" = "toggle" ]; then
  if is_active; then
    # Allow sleep again: drop the logind lock and bring hypridle back.
    kill "$(cat "$pidfile" 2>/dev/null)" 2>/dev/null
    rm -f "$pidfile"
    start_hypridle
  else
    # Stay awake: hold a logind inhibitor AND pause hypridle's idle timers.
    setsid systemd-inhibit --what=idle:sleep --who="eww" --why="User requested stay-awake" sleep infinity &
    echo $! > "$pidfile"
    stop_hypridle
  fi
  # push fresh state into eww immediately
  json=$(status_json)
  eww update "idle_icon=$(printf '%s' "$json" | jq -r '.icon')" \
             "idle_class=$(printf '%s' "$json" | jq -r '.class')" \
             "idle_tooltip=$(printf '%s' "$json" | jq -r '.tooltip')" \
    >/dev/null 2>&1
  exit 0
fi

status_json
