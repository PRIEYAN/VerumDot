#!/usr/bin/env bash
# Active window title + per-app icon for waybar.
#
# Icons are written as \u escapes rather than literal glyphs so they survive
# copy/paste and editors that mangle private-use Nerd Font codepoints.

icon_for() {
  case "$1" in
    kitty|wezterm)                        printf '' ;;
    alacritty|foot)                       printf '' ;;
    firefox)                              printf '' ;;
    chromium|brave|google-chrome|vivaldi) printf '' ;;
    code|code-oss|jetbrains-idea)         printf '' ;;
    obsidian)                             printf '' ;;
    thunar|nautilus|dolphin)              printf '' ;;
    *)                                    printf '' ;;
  esac
}

active=$(hyprctl -j activewindow 2>/dev/null)
if [ -z "$active" ] || [ "$active" = "{}" ]; then
  jq -nc '{text:("" + " No app"), tooltip:"No active window"}'
  exit 0
fi

# A malformed payload should degrade the same way an absent one does.
if ! app_class=$(printf '%s' "$active" \
      | jq -er '(.class // .app // .name // "Unknown") | ascii_downcase' 2>/dev/null); then
  jq -nc '{text:("" + " No app"), tooltip:"Active window info unavailable"}'
  exit 0
fi

title=$(printf '%s' "$active" | jq -r '.title // .class // .app // "No title"')
icon=$(icon_for "$app_class")

# Truncate long titles the way the module's max-length expects.
if [ "${#title}" -le 30 ]; then
  label="$title"
else
  label="${title:0:27}..."
fi

jq -nc --arg t "$icon $label" --arg tt "$title" '{text:$t, tooltip:$tt}'
