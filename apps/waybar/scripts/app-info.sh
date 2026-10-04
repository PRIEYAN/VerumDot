#!/usr/bin/env bash
# Active window title and per-app icon for waybar.
#
# The icon table is shared with hypr-tabs.sh (lib/ui/appicons.sh); the two
# used to keep separate, divergent copies.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use ui/waybar ui/appicons os/hypr

readonly TITLE_LIMIT=30
active=$(hypr::query activewindow)

if [[ -z $active || $active == '{}' ]]; then
  waybar::emit "${APP_ICON_DEFAULT} No app" 'No active window'
  exit 0
fi

# A malformed payload degrades the same way an absent one does.
if ! class=$(jq -er '(.class // .app // .name // "Unknown") | ascii_downcase' <<<"$active" 2>/dev/null); then
  waybar::emit "${APP_ICON_DEFAULT} No app" 'Active window info unavailable'
  exit 0
fi

title=$(jq -r '.title // .class // .app // "No title"' <<<"$active")
icon=$(appicons::for "$class")

# Truncate to what the module's max-length expects.
label=$title
(( ${#title} > TITLE_LIMIT )) && label="${title:0:$(( TITLE_LIMIT - 3 ))}..."

waybar::emit "${icon} ${label}" "$title"
