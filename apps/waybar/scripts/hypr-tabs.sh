#!/usr/bin/env bash
# Per-workspace tab for waybar: the top window's app icon, or the workspace
# number when empty. One instance per workspace, kept live by tailing the
# compositor's event socket.
#
# The icon table is shared with app-info.sh (lib/ui/appicons.sh), so a
# window cannot show one glyph on its tab and a different one in the title
# module — which it could when each kept its own copy.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/guard ui/waybar ui/appicons os/hypr

readonly PERSISTENT_WORKSPACES=9   # 1..9 always exist; 10+ are on demand
readonly RECONNECT_DELAY=0.5

workspace_id=${1:-}
[[ $workspace_id =~ ^[0-9]+$ ]] || log::usage '<workspace-number>'

# compute — the module JSON for this workspace, with class "inactive".
# emit() swaps in "active" without recomputing.
compute() {
  local top class title

  # Overflow tabs (10 and up) stay hidden until the workspace exists. This
  # is the one deliberate exception to the never-emit-empty rule below:
  # here waybar's hide-on-empty behaviour is exactly what makes the row grow
  # when you swipe past 9 and shrink again when Hyprland reaps the
  # workspace. Workspaces 1..9 are persistent and skip the check.
  if (( workspace_id > PERSISTENT_WORKSPACES )) \
     && ! hypr::query workspaces \
          | jq -e --argjson w "$workspace_id" 'any(.[]; .id == $w)' >/dev/null 2>&1; then
    waybar::emit '' '' inactive
    return
  fi

  # The lowest address on this workspace is the tab's subject — a stable
  # choice that does not flicker as focus moves between windows.
  top=$(hypr::query clients | jq -c --argjson w "$workspace_id" \
    '[.[] | select((.workspace.id // -1) == $w)] | sort_by(.address) | .[0] // empty')

  if [[ -z $top ]]; then
    waybar::emit "$workspace_id" "Workspace ${workspace_id}" inactive
    return
  fi

  class=$(jq -r '(.class // .initialClass // "") | ascii_downcase' <<<"$top")
  title=$(jq -r --arg w "Workspace ${workspace_id}" \
    '.title // .initialTitle // (.class // "") | if . == "" then $w else . end' <<<"$top")

  # appicons::for never returns empty, but the guard stays: waybar removes a
  # custom module from the bar whenever its text is empty, so an empty glyph
  # does not degrade the tab — it deletes it.
  local icon; icon=$(appicons::for "$class")
  waybar::emit "${icon:-$workspace_id}" "$title" inactive
}

# A workspace change only selects between two cached JSON lines. No hyprctl,
# no jq and no subshell on this path, so every tab reacts to the same event
# without a thundering herd of queries.
last=''
active_id=''
inactive_tab=''
active_tab=''

emit() {
  local current=$inactive_tab
  [[ $workspace_id == "$active_id" ]] && current=$active_tab
  [[ $current == "$last" ]] && return 0
  printf '%s\n' "$current"
  last=$current
}

refresh() {
  inactive_tab=$(compute)
  active_tab=${inactive_tab/\"inactive\"/\"active\"}
  emit
}

refresh_active() { active_id=$(hypr::query activeworkspace | jq -r '.id // empty'); }

select_workspace() {
  if [[ ${1:-} =~ ^[0-9]+$ ]]; then active_id=$1; else refresh_active; fi
  emit
}

trap 'exit 0' TERM INT

while :; do
  socket=$(hypr::event_socket)
  if [[ -z $socket ]] || ! guard::has socat; then
    refresh_active; refresh; sleep 1; continue
  fi

  # Subscribe before taking the initial snapshot, so changes that land
  # during it are queued rather than missed.
  exec 3< <(socat -u UNIX-CONNECT:"$socket" - 2>/dev/null)
  refresh_active
  refresh

  while IFS= read -r line; do
    event=${line%%>>*}
    data=${line#*>>}
    case $event in
      workspacev2)              select_workspace "${data%%,*}" ;;
      workspace)                select_workspace "$data" ;;
      focusedmon|focusedmonv2)  select_workspace "${data#*,}" ;;
      createworkspacev2|destroyworkspacev2)
        # Only the matching overflow slot needs to re-check its visibility.
        (( workspace_id > PERSISTENT_WORKSPACES )) \
          && [[ ${data%%,*} == "$workspace_id" ]] && refresh
        ;;
      openwindow|closewindow|movewindowv2|windowtitlev2) refresh ;;
      # Focus, floating, fullscreen and special-workspace events cannot
      # change the lowest-address window, so they are deliberately ignored.
    esac
  done <&3

  exec 3<&-
  sleep "$RECONNECT_DELAY"   # the socket died; back off before reconnecting
done
