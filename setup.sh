#!/usr/bin/env bash
#
# Install this Hyprland rice on a fresh machine.
#
# Usage:
#   ./setup.sh              # install packages + deploy config
#   ./setup.sh --config     # deploy config only (skip packages)
#   ./setup.sh --packages   # install packages only (skip deploy)
#   ./setup.sh --help
#
# After install the rice lives at:  ~/.config/hypr
# Migrate later by copying/cloning this folder anywhere and re-running
# ./setup.sh --config
#
set -euo pipefail

RICE_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
WAYBAR_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/waybar"
WALLPAPER_DIR="${HOME}/Pictures/Wallpapers"
STAMP="$(date +%Y%m%d-%H%M%S)"

DO_PACKAGES=1
DO_CONFIG=1

# ── official Arch repos ────────────────────────────────────────────────
PACMAN_PKGS=(
  # compositor + ecosystem
  hyprland hyprpaper hypridle hyprlock hyprcursor
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
  # bar / launcher / notifs / terminal
  waybar rofi mako kitty
  # audio / media
  pipewire pipewire-pulse wireplumber pamixer playerctl
  # brightness / files / utils
  brightnessctl inotify-tools jq
  grim slurp wl-clipboard swappy
  # networking / bluetooth
  network-manager-applet blueman
  # theming
  kvantum qt6ct
  # fonts
  ttf-jetbrains-mono-nerd ttf-iosevka-nerd ttf-nerd-fonts-symbols
  noto-fonts noto-fonts-emoji
  # apps used by binds / scripts
  firefox nautilus
  power-profiles-daemon
  python
)

# ── AUR (yay) ──────────────────────────────────────────────────────────
AUR_PKGS=(
  eww-git                 # fallback tries: eww, eww-debug
  spotify
  visual-studio-code-bin  # SUPER+C bind; skip if you use another editor
  kora-icon-theme         # optional; theme-install builds white folders from it
  qt5ct                   # optional Qt5 apps
)

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \?//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config|--config-only)   DO_PACKAGES=0; DO_CONFIG=1; shift ;;
    --packages|--packages-only) DO_PACKAGES=1; DO_CONFIG=0; shift ;;
    -h|--help) usage ;;
    *) die "unknown flag: $1 (try --help)" ;;
  esac
done

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }

backup_path() {
  local p=$1
  if [[ -e "$p" || -L "$p" ]]; then
    local bak="${p}.bak.${STAMP}"
    mv "$p" "$bak"
    ok "backed up $p → $bak"
  fi
}

link_force() {
  local src=$1 dst=$2
  mkdir -p "$(dirname "$dst")"
  if [[ -L "$dst" ]]; then
    rm -f "$dst"
  elif [[ -e "$dst" ]]; then
    backup_path "$dst"
  fi
  ln -s "$src" "$dst"
  ok "linked $dst → $src"
}

install_packages() {
  need_cmd pacman
  log "Installing official packages (pacman)"
  sudo pacman -Syu --needed --noconfirm "${PACMAN_PKGS[@]}"

  local aur_helper=""
  if command -v yay >/dev/null 2>&1; then
    aur_helper=yay
  elif command -v paru >/dev/null 2>&1; then
    aur_helper=paru
  else
    warn "No AUR helper (yay/paru). Skipping AUR packages: ${AUR_PKGS[*]}"
    warn "Install yay, then re-run:  ./setup.sh --packages"
    return 0
  fi

  log "Installing AUR packages ($aur_helper)"
  # eww has a few package names across AUR; try preferred then fallbacks
  local eww_ok=0
  for cand in eww-git eww eww-debug; do
    if $aur_helper -S --needed --noconfirm "$cand"; then
      eww_ok=1
      ok "eww via $cand"
      break
    fi
  done
  [[ $eww_ok -eq 1 ]] || warn "could not install eww (volume/power/calendar popups need it)"

  for pkg in "${AUR_PKGS[@]}"; do
    [[ "$pkg" == eww* ]] && continue
    $aur_helper -S --needed --noconfirm "$pkg" || warn "skipped $pkg"
  done
}

deploy_config() {
  log "Deploying rice → $TARGET"

  if [[ "$RICE_SRC" -ef "$TARGET" ]]; then
    ok "already running from $TARGET (in-place update)"
  else
    if [[ -e "$TARGET" || -L "$TARGET" ]]; then
      backup_path "$TARGET"
    fi
    mkdir -p "$(dirname "$TARGET")"
    # Preserve .git if present so the installed copy stays a repo
    rsync -a --delete \
      --exclude '.git' \
      --exclude 'current-wallpaper' \
      --exclude '*.bak.*' \
      "$RICE_SRC/" "$TARGET/"
    if [[ -d "$RICE_SRC/.git" ]]; then
      # keep history optional: copy .git too so you can pull updates in-place
      rsync -a "$RICE_SRC/.git/" "$TARGET/.git/"
    fi
    ok "copied rice to $TARGET"
  fi

  chmod +x "$TARGET"/scripts/*.sh "$TARGET"/scripts/eww/*.sh 2>/dev/null || true
  chmod +x "$TARGET"/apps/waybar/scripts/* 2>/dev/null || true
  chmod +x "$TARGET/setup.sh" "$TARGET/scripts/_paths.sh" 2>/dev/null || true

  # Waybar reads ~/.config/waybar/{config,style.css}; point them at the rice
  mkdir -p "$WAYBAR_CFG"
  link_force "$TARGET/apps/waybar/config.jsonc" "$WAYBAR_CFG/config"
  link_force "$TARGET/apps/waybar/style.css" "$WAYBAR_CFG/style.css"
  # Keep a scripts symlink for anything still calling ~/.config/waybar/scripts
  if [[ -d "$WAYBAR_CFG/scripts" && ! -L "$WAYBAR_CFG/scripts" ]]; then
    backup_path "$WAYBAR_CFG/scripts"
  fi
  link_force "$TARGET/apps/waybar/scripts" "$WAYBAR_CFG/scripts"

  # Wallpapers dir + placeholder default so wallpaper.sh / hyprlock have a target
  mkdir -p "$WALLPAPER_DIR"
  if [[ ! -f "$WALLPAPER_DIR/suf.png" ]]; then
    # tiny 1×1 dark PNG so first boot does not explode if no wallpaper yet
    python3 - <<'PY' 2>/dev/null || true
import struct,zlib,pathlib
def png(w,h,rgb):
    def chunk(t,d): return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
    raw=b''.join(b'\x00'+bytes(rgb)*w for _ in range(h))
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b'')
pathlib.Path.home().joinpath('Pictures/Wallpapers/suf.png').write_bytes(png(64,64,(10,10,10)))
PY
    ok "created placeholder $WALLPAPER_DIR/suf.png (replace with your wallpapers)"
  fi
  ln -sfn "$WALLPAPER_DIR/suf.png" "$TARGET/current-wallpaper"
  ok "current-wallpaper → $WALLPAPER_DIR/suf.png"

  # GTK file-chooser bookmarks (portable; optional)
  if [[ -f "$TARGET/apps/gtk/gtk-3.0/bookmarks.template" ]]; then
    mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0"
    sed "s|/home/USER|$HOME|g" "$TARGET/apps/gtk/gtk-3.0/bookmarks.template" \
      > "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/bookmarks"
    ok "wrote gtk-3.0/bookmarks for $USER"
  fi

  # GTK / Qt / Kvantum / portal glass theme
  if [[ -x "$TARGET/scripts/theme-install.sh" ]]; then
    log "Installing theme symlinks"
    "$TARGET/scripts/theme-install.sh" || warn "theme-install.sh reported issues"
  fi

  # Enable user services commonly needed
  systemctl --user enable --now pipewire pipewire-pulse wireplumber 2>/dev/null || true

  # Lid close: lock + blank only (no suspend/hibernate). Needs root once.
  if [[ -f "$TARGET/apps/systemd/10-lid-lock.conf" ]]; then
    if [[ -w /etc/systemd/logind.conf.d ]] || command -v sudo >/dev/null 2>&1; then
      log "Installing logind lid policy (lock only, no hibernate)"
      sudo mkdir -p /etc/systemd/logind.conf.d
      sudo cp "$TARGET/apps/systemd/10-lid-lock.conf" /etc/systemd/logind.conf.d/10-lid-lock.conf
      sudo rm -f /etc/systemd/logind.conf.d/10-lid-hibernate.conf
      sudo systemctl restart systemd-logind 2>/dev/null \
        && ok "logind updated (HandleLidSwitch=ignore)" \
        || warn "copied lid policy — reboot if lid still hibernates"
    else
      warn "skip logind lid policy (need sudo). See apps/systemd/10-lid-lock.conf"
    fi
  fi

  cat <<EOF

────────────────────────────────────────────────────────────
  Rice installed at:  $TARGET

  Next steps:
    1. Put wallpapers in:  $WALLPAPER_DIR
    2. Edit monitor if needed:  $TARGET/hypr.conf  (search eDP-1)
       Check outputs with:      hyprctl monitors
    3. Log into a Hyprland session (or:  Hyprland )
    4. Reload later with:       hyprctl reload

  Migrate to another machine:
    copy/clone this folder, then run:  ./setup.sh
────────────────────────────────────────────────────────────
EOF
}

main() {
  [[ "$(id -u)" -eq 0 ]] && die "do not run setup.sh as root (sudo is used only for pacman)"

  log "Rice source: $RICE_SRC"
  [[ $DO_PACKAGES -eq 1 ]] && install_packages
  [[ $DO_CONFIG   -eq 1 ]] && deploy_config
  log "Done."
}

main "$@"
