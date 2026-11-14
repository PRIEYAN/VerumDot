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

# ---------------------------------------------------------------------------
# Config engine: Lua (hyprland.lua) or legacy hyprlang (hyprland.conf)
# ---------------------------------------------------------------------------
# The two engines take different command syntax over the same socket. Under
# Lua, `hyprctl dispatch` evaluates a Lua expression and `hyprctl keyword` is
# gone (it says "keyword can't work with non-legacy parsers. Use eval."), so
# every action below asks which engine is live and speaks its language. That
# keeps the scripts working before, during and after a migration, and after a
# rollback, without each caller knowing there is a difference.
#
# Detection: `hyprctl eval` answers exactly "ok" under the Lua engine; the
# legacy engine refuses it. Cached for the life of the calling process.
hypr::is_lua() {
  if [[ -z ${_HYPR_ENGINE:-} ]]; then
    local out
    out=$(hyprctl eval 'return nil' 2>/dev/null)
    [[ ${out//[[:space:]]/} == ok ]] && _HYPR_ENGINE=lua || _HYPR_ENGINE=legacy
  fi
  [[ $_HYPR_ENGINE == lua ]]
}

# hypr::lua_str <text> — <text> as a double-quoted Lua string literal.
hypr::lua_str() {
  local s=${1//\\/\\\\}
  s=${s//\"/\\\"}
  printf '"%s"' "$s"
}

# hypr::dispatch_lua <lua-expr> <legacy dispatcher> [legacy args...]
# Runs one action under whichever engine is live.
hypr::dispatch_lua() {
  local lua=$1; shift
  if hypr::is_lua; then hypr::ctl dispatch "$lua"
  else hypr::ctl dispatch "$@"
  fi
}

# hypr::set_option <section.key> <lua-value> <legacy section:key> <legacy value>
# A runtime option change (the old `hyprctl keyword`); lasts until reload.
hypr::set_option() {
  local path=$1 lua_value=$2 legacy_key=$3 legacy_value=$4
  if hypr::is_lua; then
    # decoration.screen_shader -> { decoration = { screen_shader = v } }
    local open="" close="" part
    local -a parts
    IFS=. read -ra parts <<<"$path"
    for part in "${parts[@]}"; do open+="$part = { "; close+=" }"; done
    open=${open%\{ }; close=${close# \}}
    hypr::ctl eval "hl.config({ ${open}${lua_value}${close} })"
  else
    hypr::ctl keyword "$legacy_key" "$legacy_value"
  fi
}

# hypr::reload — re-read the config with the engine already in use.
hypr::reload()   { hypr::ctl reload; }

# hypr::exit — quit the compositor (logout).
hypr::exit() { hypr::dispatch_lua 'hl.dsp.exit()' exit; }

# hypr::dpms on|off — power the outputs' backlight.
hypr::dpms() {
  hypr::dispatch_lua "hl.dsp.dpms({ action = $(hypr::lua_str "$1") })" dpms "$1"
}

# hypr::monitor <output> <mode> <position> <scale> — (re)declare an output.
hypr::monitor() {
  if hypr::is_lua; then
    hypr::ctl eval "hl.monitor({ output = $(hypr::lua_str "$1"), mode = $(hypr::lua_str "$2"), position = $(hypr::lua_str "$3"), scale = $(hypr::lua_str "$4") })"
  else
    hypr::ctl keyword monitor "$1,$2,$3,$4"
  fi
}

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
hypr::set_shader() {
  hypr::set_option decoration.screen_shader "$(hypr::lua_str "$1")" decoration:screen_shader "$1"
}
hypr::clear_shader() { hypr::set_option decoration.screen_shader '""' decoration:screen_shader ""; }

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

hypr::toggle_special() {
  hypr::dispatch_lua "hl.dsp.workspace.toggle_special($(hypr::lua_str "$1"))" togglespecialworkspace "$1"
}
hypr::goto_workspace() {
  hypr::dispatch_lua "hl.dsp.focus({ workspace = $(hypr::lua_str "$1") })" workspace "$1"
}
