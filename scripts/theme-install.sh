#!/usr/bin/env bash
#
# Installs the hypr-owned theme by symlinking it into the XDG paths that
# GTK / Qt / KDE / xdg-desktop-portal insist on reading. All real content
# lives in ~/.config/hypr/apps/theme so it stays in this repo; only links
# are placed outside.
#
#   theme-install.sh          install (backs up anything it replaces once)
#   theme-install.sh uninstall  remove links and restore the .prehypr backups
#
# Pure shell.

set -u

HYPR="/home/prieyan/.config/hypr"
T="$HYPR/apps/theme"
CFG="$HOME/.config"
SHARE="$HOME/.local/share"
SUFFIX=".prehypr"

log() { printf '  %s\n' "$*"; }

# link <source> <target>: back up a real file/dir once, then symlink.
link() {
  src=$1; dst=$2
  mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ]; then
    rm -f "$dst"
  elif [ -e "$dst" ]; then
    if [ ! -e "$dst$SUFFIX" ]; then
      mv "$dst" "$dst$SUFFIX"
      log "backed up $dst -> $dst$SUFFIX"
    else
      rm -rf "$dst"
    fi
  fi
  ln -s "$src" "$dst"
  log "linked $dst"
}

unlink_restore() {
  dst=$1
  [ -L "$dst" ] && rm -f "$dst" && log "unlinked $dst"
  if [ -e "$dst$SUFFIX" ]; then
    mv "$dst$SUFFIX" "$dst"
    log "restored $dst"
  fi
}

# ── set <file> <section> <key> <value>: idempotent INI edit ─────────────
ini_set() {
  file=$1; sec=$2; key=$3; val=$4
  [ -f "$file" ] || { mkdir -p "$(dirname "$file")"; printf '[%s]\n' "$sec" > "$file"; }
  if grep -q "^\[$sec\]" "$file"; then
    if awk -v s="[$sec]" -v k="$key" '
          $0==s{inS=1;next} /^\[/{inS=0} inS && $0 ~ "^"k"="{found=1}
          END{exit !found}' "$file"; then
      # key exists in section: replace it there
      awk -v s="[$sec]" -v k="$key" -v v="$val" '
        $0==s{print;inS=1;next}
        /^\[/{inS=0}
        inS && $0 ~ "^"k"=" {print k"="v; next}
        {print}' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    else
      awk -v s="[$sec]" -v k="$key" -v v="$val" '
        {print}
        $0==s{print k"="v}' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    fi
  else
    printf '\n[%s]\n%s=%s\n' "$sec" "$key" "$val" >> "$file"
  fi
}

# ── Build a pure-white folder icon theme from an installed grey one ─────
build_white_icons() {
  src="$SHARE/icons/kora-pgrey"
  dst="$T/icons/kora-white"
  [ -d "$src" ] || { log "kora-pgrey not installed; skipping white icons"; return; }
  rm -rf "$dst"; mkdir -p "$dst/places/scalable"
  cp "$src"/places/scalable/*.svg "$dst/places/scalable/" 2>/dev/null
  for f in "$dst"/places/scalable/*.svg; do
    sed -i -E 's/fill:rgb\([0-9]+, ?[0-9]+, ?[0-9]+\)/fill:rgb(255,255,255)/g;
               s/fill:#[0-9a-fA-F]{3,8}/fill:#ffffff/g;
               s/fill="#[0-9a-fA-F]{3,8}"/fill="#ffffff"/g' "$f"
  done
  cat > "$dst/index.theme" <<'ICON'
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
  gtk-update-icon-cache -f -t "$dst" >/dev/null 2>&1
  log "built white icon theme ($(ls "$dst"/places/scalable | wc -l) icons)"
}

install_theme() {
  echo "Installing hypr theme…"

  # GTK
  link "$T/gtk-3.0/gtk.css" "$CFG/gtk-3.0/gtk.css"
  link "$T/gtk-4.0/gtk.css" "$CFG/gtk-4.0/gtk.css"

  # Portal (fixes the light "Open Folder" dialog)
  link "$T/portal/portals.conf" "$CFG/xdg-desktop-portal/portals.conf"

  # Qt color scheme
  link "$T/qt/PureBlack.conf" "$CFG/qt5ct/colors/PureBlack.conf"
  link "$T/qt/PureBlack.conf" "$CFG/qt6ct/colors/PureBlack.conf"

  # Kvantum theme + KDE color scheme
  link "$T/kvantum/PureBlackGlass" "$CFG/Kvantum/PureBlackGlass"
  link "$T/color-schemes/PureBlack.colors" "$SHARE/color-schemes/PureBlack.colors"

  # White folder icons
  build_white_icons
  [ -d "$T/icons/kora-white" ] && link "$T/icons/kora-white" "$SHARE/icons/kora-white"

  # Point the toolkits at it. These files hold other user settings, so we
  # edit keys in place rather than replacing the files.
  printf '[General]\ntheme=PureBlackGlass\n' > "$CFG/Kvantum/kvantum.kvconfig"
  log "Kvantum theme = PureBlackGlass"

  for q in qt5ct qt6ct; do
    f="$CFG/$q/$q.conf"
    [ -f "$f" ] || continue
    ini_set "$f" Appearance color_scheme_path "$CFG/$q/colors/PureBlack.conf"
    ini_set "$f" Appearance custom_palette true
    ini_set "$f" Appearance style kvantum
    [ -d "$T/icons/kora-white" ] && ini_set "$f" Appearance icon_theme kora-white
    log "configured $q"
  done

  ini_set "$CFG/kdeglobals" Icons Theme kora-white
  ini_set "$CFG/kdeglobals" General ColorScheme PureBlack
  ini_set "$CFG/dolphinrc" UiSettings ColorScheme PureBlack
  log "configured kdeglobals + dolphinrc"

  echo
  echo "Done. Restart the portal and any open apps:"
  echo "  systemctl --user restart xdg-desktop-portal-gtk xdg-desktop-portal"
  echo "Icon/font sizes are yours to set in ~/.config/dolphinrc ([IconsMode] IconSize)."
}

uninstall_theme() {
  echo "Removing hypr theme links…"
  unlink_restore "$CFG/gtk-3.0/gtk.css"
  unlink_restore "$CFG/gtk-4.0/gtk.css"
  unlink_restore "$CFG/xdg-desktop-portal/portals.conf"
  unlink_restore "$CFG/qt5ct/colors/PureBlack.conf"
  unlink_restore "$CFG/qt6ct/colors/PureBlack.conf"
  unlink_restore "$CFG/Kvantum/PureBlackGlass"
  unlink_restore "$SHARE/color-schemes/PureBlack.colors"
  unlink_restore "$SHARE/icons/kora-white"
  echo "Note: key edits in qt5ct/qt6ct/kdeglobals/dolphinrc were left as-is."
}

case "${1:-install}" in
  uninstall) uninstall_theme ;;
  *)         install_theme ;;
esac
