#!/usr/bin/env bash
# os/hypr.sh — the only module that knows how to talk to the compositor.
#
# Everything that used to call `hyprctl` or hand-build a socket path now goes
# through here. The point is replaceability: these scripts describe a desktop,
# not specifically Hyprland, and isolating the IPC keeps that true.

hypr::use core/log core/guard os/proc

# ---------------------------------------------------------------------------
# Control socket
# ---------------------------------------------------------------------------
hypr::ctl()      { proc::quiet hyprctl "$@"; }
hypr::query()    { proc::capture hyprctl -j "$@"; }
hypr::dispatch() { hypr::ctl dispatch "$@"; }
hypr::keyword()  { hypr::ctl keyword "$@"; }
hypr::reload()   { hypr::ctl reload; }

# hypr::monitors — one monitor name per line.
hypr::monitors() {
  hypr::query monitors | jq -r '.[].name' 2>/dev/null
}

# hypr::focused_monitor — the name of the monitor with input focus.
hypr::focused_monitor() {
  hypr::query monitors | jq -r 'first(.[] | select(.focused) | .name)' 2>/dev/null
}

# hypr::special_workspace_open <name> — true when the focused monitor is
# showing the named special workspace.
hypr::special_workspace_open() {
  hypr::query monitors \
    | jq -e --arg n "special:$1" 'any(.[]; .focused and .specialWorkspace.name == $n)' \
      >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Screen shader
# ---------------------------------------------------------------------------
# A named concept rather than a raw keyword, because "clear the shader" is
# the empty string and that is not self-evident at a call site.
hypr::set_shader()   { hypr::keyword decoration:screen_shader "$1"; }
hypr::clear_shader() { hypr::keyword decoration:screen_shader ""; }

# ---------------------------------------------------------------------------
# Event stream (socket2)
# ---------------------------------------------------------------------------
# hypr::runtime_dir — where this Hyprland instance keeps its sockets.
hypr::runtime_dir() { printf '%s/hypr' "$XDG_RUNTIME_DIR"; }

# hypr::event_socket — path to the event socket for the current instance,
# falling back to the most recently created one when the signature is not in
# the environment (waybar modules are spawned by waybar, which may not
# forward it). Empty if there is none.
hypr::event_socket() {
  local dir; dir=$(hypr::runtime_dir)
  if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} && -S "$dir/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock" ]]; then
    printf '%s/%s/.socket2.sock' "$dir" "$HYPRLAND_INSTANCE_SIGNATURE"
    return 0
  fi
  ls -1t "$dir"/*/.socket2.sock 2>/dev/null | head -n 1
}

# hypr::hyprpaper_socket — path hyprpaper listens on for this instance.
hypr::hyprpaper_socket() {
  printf '%s/%s/.hyprpaper.sock' "$(hypr::runtime_dir)" "${HYPRLAND_INSTANCE_SIGNATURE:-}"
}

# hypr::wait_for_socket <path> [timeout-deciseconds] — poll until a socket
# appears. Replaces the blind `sleep 1`s that raced daemon startup.
hypr::wait_for_socket() {
  local path=$1 attempts=${2:-50}
  while (( attempts-- > 0 )); do
    [[ -S $path ]] && return 0
    sleep 0.1
  done
  return 1
}

# hypr::on_event <pattern> <callback> — run <callback> once per matching
# event line, forever, reconnecting if the socket dies.
#
# This is the behaviour the clock module had inlined: a long-lived socat on
# fd 3 read with a 1s timeout, where the timeout is the clock tick and only a
# genuine EOF means reconnect. Getting that distinction wrong leaked a socat
# process per idle second, so it is written once, here.
#
# <pattern> is a case-style glob matched against the lowercased event line.
# The callback is also invoked on every tick, so it can refresh on time as
# well as on events.
hypr::on_event() {
  local pattern=$1 callback=$2 sock line rc alive

  if ! guard::has socat; then
    log::info "socat unavailable; falling back to a plain 1s tick"
    while :; do sleep 1; "$callback"; done
  fi

  while :; do
    sock=$(hypr::event_socket)
    if [[ -z $sock ]]; then
      "$callback"; sleep 1; continue
    fi

    # Process substitution, not a pipe: a pipe would run the read loop in a
    # subshell and any state the callback keeps would be discarded each pass.
    exec 3< <(socat -u UNIX-CONNECT:"$sock" - 2>/dev/null)
    alive=1
    while (( alive )); do
      IFS= read -r -t 1 -u 3 line; rc=$?
      if (( rc == 0 )); then
        # shellcheck disable=SC2254  # pattern is intentionally a glob
        case "${line,,}" in $pattern) "$callback" ;; esac
      else
        # rc > 128 is the 1s read timeout — our tick, not an error.
        # Anything else is EOF: the compositor went away, so reconnect.
        (( rc > 128 )) || alive=0
        "$callback"
      fi
    done
    exec 3<&-
    sleep 0.5
  done
}

# hypr::panel_powered — true when the compositor reports at least one output
# with its backlight on. Used to confirm a dpms-on actually took effect.
hypr::panel_powered() {
  hypr::query monitors | jq -e 'any(.[]; .dpmsStatus == true)' >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Workspaces
# ---------------------------------------------------------------------------
# hypr::active_workspace — the focused monitor's active workspace name.
hypr::active_workspace() {
  hypr::query monitors | jq -r 'map(select(.focused))[0] | .activeWorkspace.name // ""' 2>/dev/null
}

# hypr::active_special — the focused monitor's open special workspace, or "".
hypr::active_special() {
  hypr::query monitors | jq -r 'map(select(.focused))[0] | .specialWorkspace.name // ""' 2>/dev/null
}

hypr::toggle_special() { hypr::dispatch togglespecialworkspace "$1"; }
hypr::goto_workspace() { hypr::dispatch workspace "$1"; }
