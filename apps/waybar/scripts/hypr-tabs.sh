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

# Must never be empty: waybar hides a custom module whose text is "", which
# made workspaces holding an unlisted app disappear from the bar entirely.
DEFAULT_ICON='●'

icon_for() {
  # Exact match first, then substring, mirroring the old lookup order.
  case "$1" in
    kitty|wezterm)                     printf '󰄛'; return ;;
    alacritty|foot)                    printf '󰆍'; return ;;
    firefox)                           printf '󰈹'; return ;;
    chromium|chromium-browser)         printf '\U000F02AF'; return ;;
    brave|brave-browser|vivaldi)       printf '󰖟'; return ;;
    google-chrome|google-chrome-stable|google-chrome-beta|chrome)
                                       printf '\U000F02AF'; return ;;
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
    libreoffice-writer|libreoffice-startcenter|soffice) printf '󰈙'; return ;;
    libreoffice-calc)                  printf '󰈛'; return ;;
    libreoffice-impress)               printf '󰈩'; return ;;
    libreoffice-draw)                  printf '󰈟'; return ;;
    zathura|org.pwmt.zathura|evince|okular) printf '󰈦'; return ;;
    org.gnome.nautilus|nemo|pcmanfm-qt) printf '󰉋'; return ;;
    whatsapp|whatsapp-for-linux)       printf '󰖣'; return ;;
    rofi)                              printf '󰍉'; return ;;
    imv|feh|eog|loupe)                 printf '󰋩'; return ;;
    virt-manager|qemu)                 printf '󰢹'; return ;;
    org.telegram.desktop)              printf '󰔁'; return ;;
  esac
  case "$1" in
    *kitty*|*wezterm*)   printf '󰄛'; return ;;
    *alacritty*|*foot*)  printf '󰆍'; return ;;
    *firefox*)           printf '󰈹'; return ;;
    *chrom*)             printf '\U000F02AF'; return ;;
    *brave*|*vivaldi*)   printf '󰖟'; return ;;
    *code*)              printf '󰨞'; return ;;
    *obsidian*)          printf '󱓧'; return ;;
    *thunar*|*nautilus*|*dolphin*) printf '󰉋'; return ;;
    *discord*|*vesktop*) printf '󰙯'; return ;;
    *spotify*)           printf '󰓇'; return ;;
    *telegram*)          printf '󰔁'; return ;;
    *vlc*|*mpv*)         printf '󰕼'; return ;;
    *libreoffice*|*soffice*|*office*) printf '󰈙'; return ;;
    *zathura*|*evince*|*okular*|*pdf*) printf '󰈦'; return ;;
    *whatsapp*)          printf '󰖣'; return ;;
    *term*|*konsole*)    printf '󰆍'; return ;;
    *file*|*nemo*|*pcmanfm*) printf '󰉋'; return ;;
  esac
  printf '%s' "$DEFAULT_ICON"
}

compute() {
  local top app_class title icon

  # Overflow tabs (10 and up) are hidden until the workspace actually exists.
  # This is the one deliberate exception to the "never emit empty text" rule
  # below: here waybar's hide-on-empty behaviour is exactly what makes the row
  # grow when you swipe past 9 and shrink again when the workspace is emptied
  # and Hyprland reaps it. Workspaces 1-9 are persistent and skip this check.
  if [ "$workspace_id" -gt 9 ] \
     && ! hyprctl -j workspaces 2>/dev/null \
          | jq -e --argjson w "$workspace_id" 'any(.[]; .id == $w)' >/dev/null; then
    printf '{"text":"","class":"inactive","tooltip":""}\n'
    return
  fi

  # Pick the lowest address on this workspace, matching the old sort.
  top=$(hyprctl -j clients 2>/dev/null | jq -c --argjson w "$workspace_id" \
    '[.[] | select((.workspace.id // -1) == $w)] | sort_by(.address) | .[0] // empty')

  if [ -z "$top" ]; then
    jq -nc --arg t "$workspace_id" --arg c inactive \
      --arg tt "Workspace $workspace_id" '{text:$t, class:$c, tooltip:$tt}'
    return
  fi

  app_class=$(printf '%s' "$top" | jq -r '(.class // .initialClass // "") | ascii_downcase')
  title=$(printf '%s' "$top" | jq -r --arg w "Workspace $workspace_id" \
    '.title // .initialTitle // (.class // "") | if . == "" then $w else . end')
  icon=$(icon_for "$app_class")

  # Last line of defence. Waybar removes a custom module from the bar whenever
  # its text is empty, so an unlisted app -- or a table entry whose glyph got
  # stripped by an editor, which is how the chrome icons were silently lost --
  # made the whole workspace vanish. Nothing below may emit an empty string.
  [ -z "$icon" ] && icon=$DEFAULT_ICON
  [ -z "$icon" ] && icon=$workspace_id

  jq -nc --arg t "$icon" --arg c inactive --arg tt "$title" \
    '{text:$t, class:$c, tooltip:$tt}'
}

# Workspace changes only select a cached JSON line. No hyprctl, jq, or
# subshells on this path: every tab receives the same event immediately.
last=''
emit() {
  local cur="$inactive_tab"
  if [ "$workspace_id" = "$active_id" ]; then cur=$active_tab; fi
  if [ "$cur" != "$last" ]; then printf '%s\n' "$cur"; last="$cur"; fi
}

refresh() {
  inactive_tab=$(compute)
  active_tab=${inactive_tab/\"class\":\"inactive\"/\"class\":\"active\"}
  emit
}

refresh_active() {
  active_id=$(hyprctl -j activeworkspace 2>/dev/null | jq -r '.id // empty')
}

select_workspace() {
  case "$1" in
    ''|*[!0-9]*) refresh_active ;;
    *) active_id=$1 ;;
  esac
  emit
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

while :; do
  sock=$(socket2)
  if [ -z "$sock" ] || ! command -v socat >/dev/null 2>&1; then
    # No event stream available: fall back to polling.
    refresh_active; refresh; sleep 1; continue
  fi
  # Subscribe before the initial snapshot so changes during it are queued.
  exec 3< <(socat -u UNIX-CONNECT:"$sock" - 2>/dev/null)
  refresh_active
  refresh
  while IFS= read -r line; do
    event=${line%%>>*}
    data=${line#*>>}
    case "$event" in
      workspacev2) select_workspace "${data%%,*}" ;;
      workspace) select_workspace "$data" ;;
      focusedmon|focusedmonv2) select_workspace "${data#*,}" ;;
      createworkspacev2|destroyworkspacev2)
        # Only the matching overflow slot needs to check its visibility.
        if [ "$workspace_id" -gt 9 ] && [ "${data%%,*}" = "$workspace_id" ]; then
          refresh
        fi ;;
      openwindow|closewindow|movewindowv2|windowtitlev2) refresh ;;
      # Focus, floating, fullscreen and special-workspace events do not
      # change the lowest-address window used for the tab's icon/title.
    esac
  done <&3
  exec 3<&-
  sleep 0.5   # socket died; back off before reconnecting
done
