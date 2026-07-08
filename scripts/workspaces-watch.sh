#!/usr/bin/env bash
# Long-running process for eww's (deflisten workspaces ...). Emits JSON for
# nine workspace slots — {id, active, occupied, icon} — and refreshes the
# instant Hyprland fires a relevant IPC event (socket2), so 3-finger
# workspace swipes and window open/close reflect immediately.
#
# icon: an underscore for an empty workspace, else a monochrome Nerd Font
# glyph for the focused (or first) window's app in that workspace.

SLOTS=9

# --- app class -> Nerd Font glyph -----------------------------------------
# Keyed by a lowercased substring of the window's class. First match wins.
# Fallback glyph is a generic window/dot for unknown apps.
icon_for() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    *firefox*|*librewolf*|*floorp*)       printf '' ;;
    *chromium*|*chrome*|*brave*)          printf '' ;;
    *kitty*|*alacritty*|*foot*|*wezterm*|*ghostty*|*term*) printf '' ;;
    *code*|*vscodium*)                    printf '' ;;
    *nvim*|*vim*)                         printf '' ;;
    *spotify*)                            printf '' ;;
    *discord*|*vesktop*|*webcord*)        printf '' ;;
    *telegram*)                           printf '' ;;
    *thunar*|*nautilus*|*nemo*|*dolphin*|*files*) printf '' ;;
    *obsidian*)                           printf '' ;;
    *gimp*)                               printf '' ;;
    *blender*)                            printf '󰂫' ;;
    *steam*)                              printf '' ;;
    *mpv*|*vlc*)                          printf '' ;;
    *zathura*|*evince*|*pdf*)             printf '' ;;
    *slack*)                              printf '' ;;
    *obs*)                                printf '󰑋' ;;
    *libreoffice*)                        printf '' ;;
    *)                                    printf '' ;;  # generic app glyph
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
    else occs+=("false"); icons+=("_"); fi
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
