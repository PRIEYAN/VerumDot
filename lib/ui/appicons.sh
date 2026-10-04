#!/usr/bin/env bash
# ui/appicons.sh — window class to Nerd Font glyph.
#
# There were two of these tables: a long one in hypr-tabs.sh and a shorter,
# divergent one in app-info.sh, so the same window could show one icon on its
# workspace tab and a different one in the title module. One table now.

# Must never be empty — see the note on the escapes below.
readonly APP_ICON_DEFAULT='●'

declare -Ag APP_ICON_EXACT=()

# Each entry is written as an explicit codepoint escape. These are private-use
# characters: an editor or copy/paste that silently drops one leaves an empty
# string, and waybar hides any custom module whose text is empty — which is how
# the Chrome icons once vanished and took their whole workspace tab with them.
_icon() { local glyph=$1; shift; local key; for key in "$@"; do APP_ICON_EXACT[$key]=$glyph; done; }

# terminals
_icon $'\U000F011B' kitty wezterm
_icon $'\U000F018D' alacritty foot

# browsers
_icon $'\U000F0239' firefox
_icon $'\U000F02AF' chromium chromium-browser
_icon $'\U000F059F' brave brave-browser vivaldi
_icon $'\U000F02AF' google-chrome google-chrome-stable google-chrome-beta chrome

# editors
_icon $'\U000F0A1E' code code-oss visual-studio-code-bin
_icon $'\U000F05DA' jetbrains-idea
_icon $'\U000F14E7' obsidian

# file managers
_icon $'\U000F024B' thunar nautilus dolphin pcmanfm
_icon $'\U000F024B' org.gnome.nautilus nemo pcmanfm-qt

# chat
_icon $'\U000F066F' discord vesktop
_icon $'\U000F04B1' slack
_icon $'\U000F0501' telegram-desktop telegram org.telegram.desktop
_icon $'\U000F05A3' whatsapp whatsapp-for-linux

# media
_icon $'\U000F04C7' spotify spotify-launcher
_icon $'\U000F057C' vlc mpv
_icon $'\U000F04C3' pavucontrol
_icon $'\U000F02E9' imv feh eog loupe

# creative and games
_icon $'\U000F0509' gimp inkscape blender
_icon $'\U000F04D3' steam

# documents
_icon $'\U000F0219' libreoffice-writer libreoffice-startcenter soffice
_icon $'\U000F021B' libreoffice-calc
_icon $'\U000F0229' libreoffice-impress
_icon $'\U000F021F' libreoffice-draw
_icon $'\U000F0226' zathura org.pwmt.zathura evince okular

# misc
_icon $'\U000F06A9' antigravity
_icon $'\U000F0349' rofi
_icon $'\U000F08B9' virt-manager qemu

# other
_icon $'\U000F0501' org.telegram.desktop

unset -f _icon

# Substring fallbacks, tried in order after an exact miss, so that
# `firefox-developer-edition` reaches the firefox glyph instead of the
# default. Stored as a list, not a map: bash associative arrays have no
# defined iteration order, and here the first match must win deterministically.
#
# Each entry is "glob[,glob...]=glyph". The alternatives are comma-separated
# and tested one at a time rather than being written as a single `a|b` case
# pattern — a `|` inside a *variable* is matched literally by `case`, not as
# alternation, so the combined form silently never matched.
readonly -a APP_ICON_PATTERNS=(
  "*kitty*,*wezterm*=$(printf '\U000F011B')"
  "*alacritty*,*foot*=$(printf '\U000F018D')"
  "*firefox*=$(printf '\U000F0239')"
  "*chrom*=$(printf '\U000F02AF')"
  "*brave*,*vivaldi*=$(printf '\U000F059F')"
  "*code*=$(printf '\U000F0A1E')"
  "*obsidian*=$(printf '\U000F14E7')"
  "*thunar*,*nautilus*,*dolphin*=$(printf '\U000F024B')"
  "*discord*,*vesktop*=$(printf '\U000F066F')"
  "*spotify*=$(printf '\U000F04C7')"
  "*telegram*=$(printf '\U000F0501')"
  "*vlc*,*mpv*=$(printf '\U000F057C')"
  "*libreoffice*,*soffice*,*office*=$(printf '\U000F0219')"
  "*zathura*,*evince*,*okular*,*pdf*=$(printf '\U000F0226')"
  "*whatsapp*=$(printf '\U000F05A3')"
  "*term*,*konsole*=$(printf '\U000F018D')"
  "*file*,*nemo*,*pcmanfm*=$(printf '\U000F024B')"
)

# appicons::for <class> — the glyph for a window class. Never returns an
# empty string; an unknown class falls back to APP_ICON_DEFAULT.
appicons::for() {
  local class=${1,,} entry globs glyph glob
  # A window can report no class at all; bash treats an empty associative
  # subscript as an error rather than a miss, so it is handled up front.
  [[ -z $class ]] && { printf '%s' "$APP_ICON_DEFAULT"; return 0; }
  [[ -n ${APP_ICON_EXACT[$class]:-} ]] && { printf '%s' "${APP_ICON_EXACT[$class]}"; return 0; }
  for entry in "${APP_ICON_PATTERNS[@]}"; do
    globs=${entry%%=*}
    glyph=${entry#*=}
    while IFS= read -r -d, glob || [[ -n $glob ]]; do
      # shellcheck disable=SC2254  # the glob is intentionally a pattern
      case $class in $glob) printf '%s' "${glyph:-$APP_ICON_DEFAULT}"; return 0 ;; esac
    done <<<"${globs},"
  done
  printf '%s' "$APP_ICON_DEFAULT"
}
