#!/usr/bin/env bash
# Long-running process for eww's (deflisten workspaces ...). Emits JSON for
# nine workspace slots — {id, active, occupied, icon} — and refreshes the
# instant Hyprland fires a relevant IPC event (socket2), so 3-finger
# workspace swipes and window open/close reflect immediately.
#
# icon: the workspace number for an empty workspace, else a monochrome Nerd
# Font glyph for the focused (or first) window's app in that workspace.
#
# LATENCY MODEL — the two things that used to make switching feel laggy:
#   1. Every emit shelled out to hyprctl TWICE (activeworkspace + clients).
#      Each call is a fresh socket round-trip to Hyprland — the dominant cost.
#   2. A blanket 30ms debounce delayed even a single deliberate switch.
#
# Fix: the socket2 event line already carries the new active workspace id
# (e.g. "workspace>>2"). A pure workspace SWITCH therefore needs ZERO hyprctl
# calls — we update $ACTIVE from the event and re-render the cached client map
# instantly. hyprctl clients is re-fetched only on WINDOW events (open/close/
# move), which are the only events that actually change occupancy/icons, and
# those are debounced. Result: switching is near-instant; window changes still
# coalesce.

SLOTS=9

# Nerd Font glyph table as a jq object literal. Keys are lowercase substrings
# matched against the window class; first match wins (checked in listed order).
# Glyphs are \u escapes (jq decodes them) so no editor can strip the private-
# use codepoints — literal glyphs had previously been blanked on save.
#
# Order matters: more specific keys first. jq walks this list per workspace.
ICON_RULES='[
  {"m":["firefox","librewolf","floorp"],"g":"\uf269"},
  {"m":["chromium","chrome","brave"],"g":"\uf268"},
  {"m":["kitty","alacritty","foot","wezterm","ghostty","term"],"g":"\ue795"},
  {"m":["code","vscodium"],"g":"\ue70c"},
  {"m":["nvim","vim"],"g":"\ue7c5"},
  {"m":["spotify"],"g":"\uf1bc"},
  {"m":["discord","vesktop","webcord"],"g":"\uf392"},
  {"m":["telegram"],"g":"\uf2c6"},
  {"m":["thunar","nautilus","nemo","dolphin","files"],"g":"\uf07b"},
  {"m":["obsidian"],"g":"\uf016"},
  {"m":["gimp"],"g":"\uf03e"},
  {"m":["blender"],"g":"\udb80\udcab"},
  {"m":["steam"],"g":"\uf1b6"},
  {"m":["mpv","vlc"],"g":"\uf144"},
  {"m":["zathura","evince","pdf"],"g":"\uf1c1"},
  {"m":["slack"],"g":"\uf198"},
  {"m":["obs"],"g":"\udb81\udc4b"},
  {"m":["libreoffice"],"g":"\uf1c2"}
]'
GENERIC_GLYPH='"\uf2d0"'   # fallback: generic window (JSON string for fromjson)

# One jq program builds all nine slots from a clients payload + an active id.
# $active is passed as a plain integer arg (from the event line, no hyprctl).
JQ_PROG='
  # class -> glyph: first rule whose any-substring matches the lowercased class.
  def glyph($rules; $generic; $cls):
    ($cls | ascii_downcase) as $c
    | ( [ $rules[] | select(any(.m[]; . as $s | $c | contains($s))) ][0].g )
      // $generic;
  ($rules | fromjson) as $rules
  | ($generic | fromjson) as $generic
  | ($clients | fromjson) as $clients
  | [ range(1; $slots + 1) as $i
      | [ $clients[] | select(.workspace.id == $i) ] as $ws
      | ( ($ws | map(select(.focusHistoryID == 0)) + $ws)[0].class // "" ) as $cls
      | { id: $i,
          active: ($i == $active),
          occupied: ($cls != ""),
          icon: (if $cls == "" then ($i | tostring) else glyph($rules; $generic; $cls) end) }
    ]
'

# Cached raw `hyprctl clients -j` payload. Refreshed only on window events.
CLIENTS='[]'

refresh_clients() {
  local c
  c=$(hyprctl clients -j 2>/dev/null)
  [ -n "$c" ] && CLIENTS="$c"
}

# Query the active workspace once (used only at startup; afterwards the event
# stream tells us). Falls back to 1 if hyprctl is unavailable.
current_active() {
  hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // 1' 2>/dev/null || echo 1
}

# Render the bar from the CURRENT $ACTIVE + cached $CLIENTS. No hyprctl here.
emit() {
  jq -cn \
    --arg    slots   "$SLOTS" \
    --argjson active "${ACTIVE:-1}" \
    --arg    clients "$CLIENTS" \
    --arg    rules   "$ICON_RULES" \
    --arg    generic "$GENERIC_GLYPH" \
    "(\$slots | tonumber) as \$slots | $JQ_PROG"
}

# --- startup: one full fetch, then render -------------------------------------
ACTIVE=$(current_active)
refresh_clients
emit

# --- event loop ---------------------------------------------------------------
# socket2 lines look like "EVENT>>data". We split on the ">>".
#   workspace / focusedmon      -> active id changed: update $ACTIVE, emit NOW
#   open/close/move window etc. -> occupancy changed: mark clients stale
# Window events are debounced (30ms quiet window) so a burst refetches clients
# once; workspace switches are NEVER debounced — they render immediately from
# the cached map, so the highlighted workspace tracks your input with no lag.
#
# read's exit status distinguishes: >128 timeout (flush stale clients), other
# nonzero EOF (Hyprland gone -> exit).
sig="$XDG_RUNTIME_DIR/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
if command -v socat >/dev/null 2>&1 && [ -S "$sig" ]; then
  socat -U - "UNIX-CONNECT:$sig" 2>/dev/null | while :; do
    if [ -n "$stale" ]; then read -r -t 0.03 line; rc=$?
    else                     read -r          line; rc=$?
    fi
    if [ "$rc" -gt 128 ]; then          # quiet window elapsed: clients settled
      refresh_clients; emit; stale=
      continue
    elif [ "$rc" -ne 0 ]; then          # EOF: socat/Hyprland went away
      break
    fi

    ev=${line%%>>*}       # event name
    data=${line#*>>}      # payload after ">>"
    case "$ev" in
      workspace|focusedworkspace|activeworkspacev2|workspacev2)
        # payload is (id) or (id,name) depending on event; take leading digits
        newid=${data%%,*}
        case "$newid" in
          ''|*[!0-9]*) : ;;             # non-numeric (named ws): ignore id
          *) ACTIVE=$newid; emit ;;     # switch: instant re-render, no hyprctl
        esac
        ;;
      focusedmon)
        # "focusedmon>>MONITOR,WSNAME" — ws is a name, not always numeric.
        wsname=${data#*,}
        case "$wsname" in
          ''|*[!0-9]*) : ;;
          *) ACTIVE=$wsname; emit ;;
        esac
        ;;
      openwindow|closewindow|movewindow|movewindowv2|windowtitle|urgent|\
      createworkspace|destroyworkspace|activewindow|activewindowv2)
        stale=1 ;;                      # occupancy/icons may have changed
    esac
  done
else
  # Fallback: no socat/socket. Poll everything on a slow timer.
  while true; do
    ACTIVE=$(current_active); refresh_clients; emit
    sleep 1
  done
fi
