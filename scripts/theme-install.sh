#!/usr/bin/env bash
# Installs the hypr-owned theme by symlinking it into the XDG paths that
# GTK, Qt, KDE and xdg-desktop-portal insist on reading.
#
# All real content stays in apps/theme so it remains part of this repo; only
# links are placed outside it.
#
#   theme-install.sh            install (backing up anything it replaces, once)
#   theme-install.sh uninstall  remove the links and restore the backups
#
# The set of links is declared once, in THEME_LINKS, and both install and
# uninstall walk it. They used to carry separate hand-maintained lists, so
# adding a link meant remembering to add its removal too.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/cli core/guard core/log core/paths os/proc os/ini os/symlink

HYPR_LOG_LEVEL=${HYPR_LOG_LEVEL:-info}   # this command narrates by design

readonly CONFIG="${XDG_CONFIG_HOME}"
readonly SHARE="${XDG_DATA_HOME}"
readonly WHITE_ICONS="${HYPR_THEME}/icons/kora-white"

# "source-under-apps/theme : absolute target"
readonly -a THEME_LINKS=(
  "gtk-3.0/gtk.css                 : ${CONFIG}/gtk-3.0/gtk.css"
  "gtk-4.0/gtk.css                 : ${CONFIG}/gtk-4.0/gtk.css"
  "portal/portals.conf             : ${CONFIG}/xdg-desktop-portal/portals.conf"
  "qt/PureBlack.conf               : ${CONFIG}/qt5ct/colors/PureBlack.conf"
  "qt/PureBlack.conf               : ${CONFIG}/qt6ct/colors/PureBlack.conf"
  "kvantum/PureBlackGlass          : ${CONFIG}/Kvantum/PureBlackGlass"
  "color-schemes/PureBlack.colors  : ${SHARE}/color-schemes/PureBlack.colors"
  "icons/kora-white                : ${SHARE}/icons/kora-white"
)

# link_parts <entry> — split an entry into SOURCE and TARGET, trimmed.
link_parts() {
  local entry=$1
  SOURCE="${HYPR_THEME}/$(printf '%s' "${entry%%:*}" | xargs)"
  TARGET=$(printf '%s' "${entry#*:}" | xargs)
}

# ---------------------------------------------------------------------------
# White folder icons, derived from an installed grey theme
# ---------------------------------------------------------------------------
build_white_icons() {
  local source="${SHARE}/icons/kora-pgrey" file count
  if [[ ! -d $source ]]; then
    log::warn 'kora-pgrey is not installed; skipping the white icon theme'
    return 1
  fi

  rm -rf -- "$WHITE_ICONS"
  mkdir -p -- "${WHITE_ICONS}/places/scalable"
  cp "$source"/places/scalable/*.svg "${WHITE_ICONS}/places/scalable/" 2>/dev/null

  # Every fill becomes white, in all three spellings these SVGs use.
  for file in "${WHITE_ICONS}"/places/scalable/*.svg; do
    sed -i -E 's/fill:rgb\([0-9]+, ?[0-9]+, ?[0-9]+\)/fill:rgb(255,255,255)/g;
               s/fill:#[0-9a-fA-F]{3,8}/fill:#ffffff/g;
               s/fill="#[0-9a-fA-F]{3,8}"/fill="#ffffff"/g' "$file"
  done

  cat >"${WHITE_ICONS}/index.theme" <<'ICON'
[Icon Theme]
Name=kora-white
Comment=kora-pgrey with pure white folder icons
Inherits=kora-pgrey,breeze-dark,Adwaita,hicolor
Directories=places/scalable

[places/scalable]
Size=48
MinSize=8
MaxSize=512
Context=Places
Type=Scalable
ICON

  guard::has gtk-update-icon-cache && proc::quiet gtk-update-icon-cache -f -t "$WHITE_ICONS"
  count=$(find "${WHITE_ICONS}/places/scalable" -name '*.svg' | wc -l)
  log::info "built the white icon theme (${count} icons)"
}

# ---------------------------------------------------------------------------
cmd_install() {
  log::info 'installing the hypr theme'

  build_white_icons || true

  local entry SOURCE TARGET
  for entry in "${THEME_LINKS[@]}"; do
    link_parts "$entry"
    # The icon theme is only linked when it was actually built.
    [[ -e $SOURCE ]] || { log::warn "skipping absent source ${SOURCE}"; continue; }
    symlink::install "$SOURCE" "$TARGET"
  done

  # These files hold the user's own settings, so individual keys are edited
  # rather than the files being replaced.
  mkdir -p -- "${CONFIG}/Kvantum"
  printf '[General]\ntheme=PureBlackGlass\n' >"${CONFIG}/Kvantum/kvantum.kvconfig"
  log::info 'Kvantum theme = PureBlackGlass'

  local toolkit file
  for toolkit in qt5ct qt6ct; do
    file="${CONFIG}/${toolkit}/${toolkit}.conf"
    [[ -f $file ]] || continue
    ini::set "$file" Appearance color_scheme_path "${CONFIG}/${toolkit}/colors/PureBlack.conf"
    ini::set "$file" Appearance custom_palette true
    ini::set "$file" Appearance style kvantum
    [[ -d $WHITE_ICONS ]] && ini::set "$file" Appearance icon_theme kora-white
    log::info "configured ${toolkit}"
  done

  ini::set "${CONFIG}/kdeglobals" Icons Theme kora-white
  ini::set "${CONFIG}/kdeglobals" General ColorScheme PureBlack
  ini::set "${CONFIG}/dolphinrc" UiSettings ColorScheme PureBlack
  log::info 'configured kdeglobals and dolphinrc'

  cat <<'NOTE'

Done. Restart the portal and any open apps:
  systemctl --user restart xdg-desktop-portal-gtk xdg-desktop-portal

Icon and font sizes are yours to set in ~/.config/dolphinrc ([IconsMode] IconSize).
NOTE
}

cmd_uninstall() {
  log::info 'removing the hypr theme links'
  local entry SOURCE TARGET
  for entry in "${THEME_LINKS[@]}"; do
    link_parts "$entry"
    symlink::remove "$TARGET"
  done
  log::info 'key edits in qt5ct/qt6ct/kdeglobals/dolphinrc were left as they are'
}

declare -A COMMANDS=(
  [install]="cmd_install|symlink the theme into the XDG paths (the default)"
  [uninstall]="cmd_uninstall|remove the links and restore backups"
)

cli::dispatch "${1:-install}" "${@:2}"
