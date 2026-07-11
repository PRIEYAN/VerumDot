#!/usr/bin/env bash
# Long-running process for eww's (deflisten workspaces ...). Emits JSON for
# nine workspace slots — {id, active, occupied, icon} — and refreshes the
# instant Hyprland fires a relevant IPC event (socket2), so 3-finger
# workspace swipes and window open/close reflect immediately.
#
# icon: the workspace number for an empty workspace, else a monochrome Nerd
# Font glyph for the focused (or first) window's app in that workspace.
#
# LATENCY MODEL — what used to make the bar lag, especially under heavy CPU load:
#   1. Every emit shelled out to hyprctl TWICE (activeworkspace + clients).
#   2. A blanket 30ms debounce delayed even a single deliberate switch.
#   3. Every emit spawned a fresh `jq` process. A burst of switches (held
#      keybind / swipe) queued one jq PER event behind your heavy task on the
#      run queue, so the highlight trailed your input by hundreds of ms.
#   4. Continuous window events (a busy task churning windows) could keep
#      feeding the debounce read before its quiet window elapsed, starving the
#      client refresh so the bar "stopped working".
#
# Fix: the socket2 event line already carries the new active workspace id
# (e.g. "workspace>>2"). We split the render into two parts:
#   * the PER-SLOT BASE  {id, occupied, icon}  — depends only on the window map,
#     so it's computed by jq ONCE per window-event burst and cached in bash
#     arrays (OCC[], ICON[]).
#   * the ACTIVE flag — changes on every switch, stitched in by PURE BASH.
# A workspace SWITCH therefore spawns NO jq and NO hyprctl: it just re-prints
# the cached base with a new active index. jq/hyprctl run only on window events,
# and those are both debounced AND force-flushed so they can never be starved.

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
  {"m":["obs"],"g":"\udb84\udc4b"},
  {"m":["libreoffice"],"g":"\uf1c2"}
]'
GENERIC_GLYPH='"\uf2d0"'   # fallback: generic window (JSON string for fromjson)

# jq program: from a raw `hyprctl clients -j` payload, produce ONE line per slot
# — "<occupied 0|1>\t<icon>" — with the glyph already resolved. This is the only
# jq we run, and only when the window map changes. The active flag is NOT here;
# it's applied in bash so a switch needs no jq. icon is emitted WITHOUT quotes so
# bash can splice it straight into the final JSON string.
JQ_BASE='
  def glyph($rules; $generic; $cls):
    ($cls | ascii_downcase) as $c
    | ( [ $rules[] | select(any(.m[]; . as $s | $c | contains($s))) ][0].g )
      // $generic;
  ($rules   | fromjson) as $rules
  | ($generic | fromjson) as $generic
  | ($clients | fromjson) as $clients
  | range(1; $slots + 1) as $i
  | [ $clients[] | select(.workspace.id == $i) ] as $ws
  | ( ($ws | map(select(.focusHistoryID == 0)) + $ws)[0].class // "" ) as $cls
  | (if $cls == "" then 0 else 1 end) as $occ
  | (if $cls == "" then ($i | tostring) else glyph($rules; $generic; $cls) end) as $icon
  | "\($occ)\t\($icon)"
'

# Per-slot cached base, filled by refresh_clients(). Indices 1..SLOTS.
declare -a OCC ICON
# Seed a safe default so emit() works before the first client fetch returns.
for i in $(seq 1 "$SLOTS"); do OCC[$i]=0; ICON[$i]="$i"; done

# Recompute OCC[]/ICON[] from a fresh `hyprctl clients -j`. This is the ONLY
# place jq or hyprctl run. Called on startup and on window-event bursts.
refresh_clients() {
  local c out i=1 occ icon
  c=$(hyprctl clients -j 2>/dev/null)
  [ -n "$c" ] || return                    # keep previous cache on failure
  out=$(jq -rn \
    --arg    slots   "$SLOTS" \
    --arg    clients "$c" \
    --arg    rules   "$ICON_RULES" \
    --arg    generic "$GENERIC_GLYPH" \
    "(\$slots | tonumber) as \$slots | $JQ_BASE" 2>/dev/null) || return
  # Read the SLOTS lines back into the arrays: "<occ>\t<icon>" per line.
  while IFS=$'\t' read -r occ icon; do
    OCC[$i]="$occ"; ICON[$i]="$icon"
    i=$((i + 1))
  done <<< "$out"
}

# Query the active workspace once (used only at startup; afterwards the event
# stream tells us). Falls back to 1 if hyprctl is unavailable.
current_active() {
  hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // 1' 2>/dev/null || echo 1
}

# Render the bar from the CURRENT $ACTIVE + cached OCC[]/ICON[]. PURE BASH:
# no jq, no hyprctl — this is what makes a switch feel instant. Builds the same
# {id, active, occupied, icon} array the widget already consumes. icon values
# are pre-escaped jq output (glyphs or a bare number) and are spliced verbatim
# between quotes, so the result is valid JSON.
emit() {
  local i out="" sep="" active occ
  for i in $(seq 1 "$SLOTS"); do
    if [ "$i" = "${ACTIVE:-1}" ]; then active=true; else active=false; fi
    if [ "${OCC[$i]}" = "1" ]; then occ=true; else occ=false; fi
    out="${out}${sep}{\"id\":$i,\"active\":$active,\"occupied\":$occ,\"icon\":\"${ICON[$i]}\"}"
    sep=","
  done
  printf '[%s]\n' "$out"
}

# --- startup: one full fetch, then render -------------------------------------
ACTIVE=$(current_active)
refresh_clients
emit

# --- event loop ---------------------------------------------------------------
# socket2 lines look like "EVENT>>data". We split on the ">>".
#   workspace / focusedmon      -> active id changed: update $ACTIVE, emit NOW
#   open/close/move window etc. -> occupancy changed: mark clients stale
#
# Debounce with a HARD CEILING so a continuous stream of window events can't
# starve the refresh: we coalesce for up to ~30ms of quiet, but force a refresh
# once 'stale' has been pending across a few reads regardless. Workspace
# switches are NEVER debounced — they render immediately from the cached map.
#
# read's exit status distinguishes: >128 timeout (flush stale clients), other
# nonzero EOF (Hyprland gone -> exit).
sig="$XDG_RUNTIME_DIR/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
if command -v socat >/dev/null 2>&1 && [ -S "$sig" ]; then
  pending=0                                 # how many reads 'stale' has waited
  socat -U - "UNIX-CONNECT:$sig" 2>/dev/null | while :; do
    if [ -n "$stale" ]; then read -r -t 0.03 line; rc=$?
    else                     read -r          line; rc=$?
    fi
    if [ "$rc" -gt 128 ]; then              # quiet window elapsed: clients settled
      refresh_clients; emit; stale=; pending=0
      continue
    elif [ "$rc" -ne 0 ]; then              # EOF: socat/Hyprland went away
      break
    fi

    ev=${line%%>>*}       # event name
    data=${line#*>>}      # payload after ">>"
    case "$ev" in
      workspace|focusedworkspace|activeworkspacev2|workspacev2)
        # payload is (id) or (id,name) depending on event; take leading digits
        newid=${data%%,*}
        case "$newid" in
          ''|*[!0-9]*) : ;;                 # non-numeric (named ws): ignore id
          *) ACTIVE=$newid; emit ;;         # switch: instant re-render, no jq
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
        stale=1                             # occupancy/icons may have changed
        pending=$((pending + 1))
        # Hard ceiling: if window events keep arriving without a quiet gap, don't
        # let the refresh starve — flush after a few coalesced events.
        if [ "$pending" -ge 8 ]; then
          refresh_clients; emit; stale=; pending=0
        fi
        ;;
    esac
  done
else
  # Fallback: no socat/socket. Poll everything on a slow timer.
  while true; do
    ACTIVE=$(current_active); refresh_clients; emit
    sleep 1
  done
fi
