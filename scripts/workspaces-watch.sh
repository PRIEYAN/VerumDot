#!/usr/bin/env bash
# Long-running process for eww's (deflisten workspaces ...). Emits JSON for
# nine workspace slots — {id, active, occupied, icon} — and refreshes the
# instant Hyprland fires a relevant IPC event (socket2), so 3-finger
# workspace swipes and window open/close reflect immediately.
#
# icon: the workspace number for an empty workspace, else a monochrome Nerd
# Font glyph for the focused (or first) window's app in that workspace.

SLOTS=9

# --- app class -> Nerd Font glyph -----------------------------------------
# Keyed by a lowercased substring of the window's class. First match wins.
# Fallback glyph is a generic window for unknown apps.
#
# Glyphs are stored as \x UTF-8 byte escapes (printf %b), NOT as literal
# characters. Some editors silently strip Nerd Font private-use codepoints on
# save — which had blanked every icon here. Escapes are plain ASCII and survive
# any editor. Comment shows the Nerd Font codepoint for each.
icon_for() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    *firefox*|*librewolf*|*floorp*)       printf '%b' '\xef\x89\xa9' ;; # U+F269
    *chromium*|*chrome*|*brave*)          printf '%b' '\xef\x89\xa8' ;; # U+F268
    *kitty*|*alacritty*|*foot*|*wezterm*|*ghostty*|*term*) printf '%b' '\xee\x9e\x95' ;; # U+E795
    *code*|*vscodium*)                    printf '%b' '\xee\x9c\x8c' ;; # U+E70C
    *nvim*|*vim*)                         printf '%b' '\xee\x9f\x85' ;; # U+E7C5
    *spotify*)                            printf '%b' '\xef\x86\xbc' ;; # U+F1BC
    *discord*|*vesktop*|*webcord*)        printf '%b' '\xef\x8e\x92' ;; # U+F392
    *telegram*)                           printf '%b' '\xef\x8b\x86' ;; # U+F2C6
    *thunar*|*nautilus*|*nemo*|*dolphin*|*files*) printf '%b' '\xef\x81\xbb' ;; # U+F07B
    *obsidian*)                           printf '%b' '\xef\x80\x96' ;; # U+F016
    *gimp*)                               printf '%b' '\xef\x80\xbe' ;; # U+F03E
    *blender*)                            printf '%b' '\xf3\xb0\x82\xab' ;; # U+F00AB
    *steam*)                              printf '%b' '\xef\x86\xb6' ;; # U+F1B6
    *mpv*|*vlc*)                          printf '%b' '\xef\x85\x84' ;; # U+F144
    *zathura*|*evince*|*pdf*)             printf '%b' '\xef\x87\x81' ;; # U+F1C1
    *slack*)                              printf '%b' '\xef\x86\x98' ;; # U+F198
    *obs*)                                printf '%b' '\xf3\xb0\x91\x8b' ;; # U+F044B
    *libreoffice*)                        printf '%b' '\xef\x87\x82' ;; # U+F1C2
    *)                                    printf '%b' '\xef\x8b\x90' ;; # U+F2D0 generic window
  esac
}

emit() {
  local active clients i
  active=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id // 0')
  clients=$(hyprctl clients -j 2>/dev/null)
  [ -z "$clients" ] && clients="[]"

  # Per slot, resolve the focused/first window class -> glyph in the shell
  # (the case-map lives here), then let jq assemble the final array so the
  # JSON is always well-formed.
  local ids=() actives=() occs=() icons=()
  for ((i = 1; i <= SLOTS; i++)); do
    local cls
    cls=$(printf '%s' "$clients" | jq -r --argjson ws "$i" '
      [ .[] | select(.workspace.id == $ws) ]
      | (map(select(.focusHistoryID == 0)) + .)   # prefer focused window
      | .[0].class // ""
    ')
    ids+=("$i")
    [ "$i" = "$active" ] && actives+=("true") || actives+=("false")
    if [ -n "$cls" ]; then occs+=("true"); icons+=("$(icon_for "$cls")")
    else occs+=("false"); icons+=("$i"); fi
  done

  jq -cn \
    --argjson ids   "[$(IFS=,; echo "${ids[*]}")]" \
    --argjson active "[$(IFS=,; echo "${actives[*]}")]" \
    --argjson occ   "[$(IFS=,; echo "${occs[*]}")]" \
    --args '$ids | to_entries | map({
              id: .value,
              active: ($active[.key]),
              occupied: ($occ[.key]),
              icon: ($ARGS.positional[.key])
            })' "${icons[@]}"
}

emit

# Subscribe to Hyprland's event socket and re-emit on any workspace/window
# change. Falls back to a slow poll if socat or the socket is unavailable.
sig="$XDG_RUNTIME_DIR/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
if command -v socat >/dev/null 2>&1 && [ -S "$sig" ]; then
  socat -U - "UNIX-CONNECT:$sig" 2>/dev/null | while read -r line; do
    case "$line" in
      workspace*|createworkspace*|destroyworkspace*|focusedmon*|\
      openwindow*|closewindow*|movewindow*|activewindow*|urgent*)
        emit ;;
    esac
  done
else
  while true; do sleep 1; emit; done
fi
