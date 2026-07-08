#!/usr/bin/env bash
# Long-running process for eww's (deflisten workspaces ...). Emits JSON for
# nine workspace slots — {id, active, occupied, icon} — and refreshes the
# instant Hyprland fires a relevant IPC event (socket2), so 3-finger
# workspace swipes and window open/close reflect immediately.
#
# icon: the workspace number for an empty workspace, else a monochrome Nerd
# Font glyph for the focused (or first) window's app in that workspace.
#
# LATENCY: the whole 9-slot array is built in ONE jq pass (below). Earlier
# versions forked ~20 processes per event (a jq + subshell per slot); that
# per-event cost is what made switching feel laggy. We now spawn only
# hyprctl activeworkspace + hyprctl clients + a single jq — and coalesce
# bursts of events with a tiny debounce so a swipe emits once, not N times.

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

# One jq program builds all nine slots from a single clients payload:
#   - group clients by workspace id
#   - per slot: occupied? focused/first window's class -> glyph via ICON_RULES
#   - empty slot -> its number as the icon
JQ_PROG='
  # class -> glyph: first rule whose any-substring matches the lowercased class.
  # $rules is bound below; def is top-level so it sees it.
  def glyph($rules; $generic; $cls):
    ($cls | ascii_downcase) as $c
    | ( [ $rules[] | select(any(.m[]; . as $s | $c | contains($s))) ][0].g )
      // $generic;
  ($rules | fromjson) as $rules
  # $generic arrives as a JSON string literal ("\uXXXX") so decode it too
  | ($generic | fromjson) as $generic
  | (($active | fromjson).id // 0) as $active
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

emit() {
  local active clients
  active=$(hyprctl activeworkspace -j 2>/dev/null); [ -z "$active" ] && active='{}'
  clients=$(hyprctl clients -j 2>/dev/null);        [ -z "$clients" ] && clients='[]'

  jq -cn \
    --arg slots   "$SLOTS" \
    --arg active  "$active" \
    --arg clients "$clients" \
    --arg rules   "$ICON_RULES" \
    --arg generic "$GENERIC_GLYPH" \
    "(\$slots | tonumber) as \$slots | $JQ_PROG"
}

emit

# Subscribe to Hyprland's event socket and re-emit on any workspace/window
# change. Falls back to a slow poll if socat or the socket is unavailable.
#
# Debounce: a swipe or window shuffle fires several events back-to-back. We
# mark "dirty" on each and flush after a short quiet window, so we emit once
# per burst instead of running the whole pipeline per event. ~30ms is below
# human-perceptible latency yet coalesces near-simultaneous events.
sig="$XDG_RUNTIME_DIR/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
if command -v socat >/dev/null 2>&1 && [ -S "$sig" ]; then
  # Read events. When idle we BLOCK (no timeout) so the loop sleeps until the
  # next event — no busy polling. Once an event marks us dirty, we switch to a
  # 30ms timeout so a burst (swipe = several events) coalesces into ONE emit
  # when the quiet window elapses. read's exit status tells timeout from EOF:
  #   >128  -> timed out       (flush the pending burst)
  #   >0    -> pipe closed/EOF  (Hyprland gone: leave the loop)
  socat -U - "UNIX-CONNECT:$sig" 2>/dev/null | while :; do
    if [ -n "$dirty" ]; then read -r -t 0.03 line; rc=$?
    else                       read -r          line; rc=$?
    fi
    if [ "$rc" -gt 128 ]; then           # timeout: quiet window elapsed
      emit; dirty=
      continue
    elif [ "$rc" -ne 0 ]; then           # EOF: socat/Hyprland went away
      break
    fi
    case "$line" in
      workspace*|createworkspace*|destroyworkspace*|focusedmon*|\
      openwindow*|closewindow*|movewindow*|activewindow*|urgent*)
        dirty=1 ;;
    esac
  done
else
  while true; do sleep 1; emit; done
fi
