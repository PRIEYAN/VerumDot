#!/usr/bin/env bash
# Per-workspace tab for waybar: shows the top window's app icon, or the
# workspace number when empty. One instance per workspace, kept live by
# tailing Hyprland's event socket.
#
# Icons use \u escapes so the private-use Nerd Font codepoints survive
# editors and copy/paste.

workspace_id="$1"
case "$workspace_id" in
  ''|*[!0-9]*) exit 0 ;;
esac

DEFAULT_ICON=''

icon_for() {
  # Exact match first, then substring, mirroring the old lookup order.
  case "$1" in
    kitty|wezterm)                     printf '󰄛'; return ;;
    alacritty|foot)                    printf '󰆍'; return ;;
    firefox)                           printf '󰈹'; return ;;
    chromium)                          printf ''; return ;;
    brave|brave-browser|vivaldi)       printf '󰖟'; return ;;
    google-chrome)                     printf ''; return ;;
    code|code-oss|visual-studio-code-bin) printf '󰨞'; return ;;
    jetbrains-idea)                    printf '󰗚'; return ;;
    obsidian)                          printf '󱓧'; return ;;
    thunar|nautilus|dolphin|pcmanfm)   printf '󰉋'; return ;;
    discord|vesktop)                   printf '󰙯'; return ;;
    slack)                             printf '󰒱'; return ;;
    spotify|spotify-launcher)          printf '󰓇'; return ;;
    telegram-desktop|telegram|org.telegram.desktop) printf '󰔁'; return ;;
    vlc|mpv)                           printf '󰕼'; return ;;
    gimp|inkscape|blender)             printf '󰔉'; return ;;
    steam)                             printf '󰓓'; return ;;
    pavucontrol)                       printf '󰓃'; return ;;
    antigravity)                       printf '󰚩'; return ;;
  esac
  case "$1" in
    *kitty*|*wezterm*)   printf '󰄛'; return ;;
    *alacritty*|*foot*)  printf '󰆍'; return ;;
    *firefox*)           printf '󰈹'; return ;;
    *chrom*)             printf ''; return ;;
    *brave*|*vivaldi*)   printf '󰖟'; return ;;
    *code*)              printf '󰨞'; return ;;
    *obsidian*)          printf '󱓧'; return ;;
    *thunar*|*nautilus*|*dolphin*) printf '󰉋'; return ;;
    *discord*|*vesktop*) printf '󰙯'; return ;;
    *spotify*)           printf '󰓇'; return ;;
    *telegram*)          printf '󰔁'; return ;;
    *vlc*|*mpv*)         printf '󰕼'; return ;;
  esac
  printf '%s' "$DEFAULT_ICON"
}

compute() {
  local active_id clients top app_class title icon cls
  active_id=$(hyprctl -j activeworkspace 2>/dev/null | jq -r '.id // empty')

  # Pick the lowest address on this workspace, matching the old sort.
  top=$(hyprctl -j clients 2>/dev/null | jq -c --argjson w "$workspace_id" \
    '[.[] | select((.workspace.id // -1) == $w)] | sort_by(.address) | .[0] // empty')

  if [ "$workspace_id" = "$active_id" ]; then cls=active; else cls=inactive; fi

  if [ -z "$top" ]; then
    jq -nc --arg t "$workspace_id" --arg c "$cls" \
      --arg tt "Workspace $workspace_id" '{text:$t, class:$c, tooltip:$tt}'
    return
  fi

  app_class=$(printf '%s' "$top" | jq -r '(.class // .initialClass // "") | ascii_downcase')
  title=$(printf '%s' "$top" | jq -r --arg w "Workspace $workspace_id" \
    '.title // .initialTitle // (.class // "") | if . == "" then $w else . end')
  icon=$(icon_for "$app_class")

  jq -nc --arg t "$icon" --arg c "$cls" --arg tt "$title" \
    '{text:$t, class:$c, tooltip:$tt}'
}

# Emit only on change, so waybar is not redrawn needlessly.
last=''
emit() {
  local cur; cur=$(compute)
  if [ "$cur" != "$last" ]; then printf '%s\n' "$cur"; last="$cur"; fi
}

socket2() {
  local dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr"
  if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] \
     && [ -S "$dir/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" ]; then
    printf '%s' "$dir/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
    return 0
  fi
  # Fall back to the most recently touched instance.
  ls -1t "$dir"/*/.socket2.sock 2>/dev/null | head -1
}

trap 'exit 0' TERM INT

emit
while :; do
  sock=$(socket2)
  if [ -z "$sock" ] || ! command -v socat >/dev/null 2>&1; then
    # No event stream available: fall back to polling.
    emit; sleep 1; continue
  fi
  # Recompute on any event that can change what this tab shows.
  # Process substitution, not a pipe: a piped `while` runs in a subshell, so
  # the `last` used for change-detection would never persist between events.
  while IFS= read -r line; do
    case "${line,,}" in
      *workspace*|*activewindow*|*openwindow*|*closewindow*|*movewindow*|\
      *windowtitle*|*changefloatingmode*|*fullscreen*|*focusedmon*) emit ;;
    esac
  done < <(socat -u UNIX-CONNECT:"$sock" - 2>/dev/null)
  sleep 0.5   # socket died; back off before reconnecting
done
