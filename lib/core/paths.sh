#!/usr/bin/env bash
# core/paths.sh — every filesystem location this rice knows about.
#
# Single responsibility: naming. Nothing here touches the disk. Scripts ask
# for a path by meaning ("the rofi theme directory", "the brightness boost
# state file") rather than rebuilding "$HOME/.cache/..." by hand, so moving a
# file is one edit here instead of a grep across forty scripts.

# ---- XDG base directories (the spec's own defaults) -----------------------
: "${XDG_CONFIG_HOME:=${HOME}/.config}"
: "${XDG_CACHE_HOME:=${HOME}/.cache}"
: "${XDG_DATA_HOME:=${HOME}/.local/share}"
: "${XDG_STATE_HOME:=${HOME}/.local/state}"
: "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
export XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_RUNTIME_DIR

# ---- the rice itself ------------------------------------------------------
# HYPR_HOME is set by bootstrap.sh from the library's own location, so a
# clone at any path (or a symlinked ~/.config/hypr) resolves correctly.
readonly HYPR_SCRIPTS="${HYPR_HOME}/scripts"
readonly HYPR_APPS="${HYPR_HOME}/apps"
readonly HYPR_SHADERS="${HYPR_HOME}/shaders"

readonly HYPR_ROFI="${HYPR_APPS}/rofi"
readonly HYPR_EWW="${HYPR_APPS}/eww"
readonly HYPR_WAYBAR="${HYPR_APPS}/waybar"
readonly HYPR_WAYBAR_SCRIPTS="${HYPR_WAYBAR}/scripts"
readonly HYPR_QUICKSHELL="${HYPR_APPS}/quickshell"
readonly HYPR_THEME="${HYPR_APPS}/theme"
readonly HYPR_HYPRLOCK_CONF="${HYPR_APPS}/hyprlock/hyprlock.conf"

# ---- per-user runtime trees ----------------------------------------------
# cache  — regenerable (thumbnails, downloaded art)
# state  — must survive a reboot (chosen wallpaper, fan mode, todo list)
# run    — must NOT survive a reboot (pids, sockets, locks)
readonly HYPR_CACHE_DIR="${XDG_CACHE_HOME}/hypr"
readonly HYPR_STATE_DIR="${XDG_STATE_HOME}/hypr"
readonly HYPR_DATA_DIR="${XDG_DATA_HOME}/hypr"
readonly HYPR_RUN_DIR="${XDG_RUNTIME_DIR}/hypr-rice"

# paths::ensure_dirs — create the runtime trees. Called by modules that
# write, not at load time, so a read-only query script touches nothing.
paths::ensure_dirs() {
  mkdir -p -- "$HYPR_CACHE_DIR" "$HYPR_STATE_DIR" "$HYPR_DATA_DIR" "$HYPR_RUN_DIR"
}

# paths::rofi_theme <name> — absolute path of a .rasi theme by bare name.
paths::rofi_theme() { printf '%s/%s.rasi' "$HYPR_ROFI" "$1"; }

# paths::quickshell <name> — absolute path of a quickshell shell directory.
paths::quickshell() { printf '%s/%s' "$HYPR_QUICKSHELL" "$1"; }

# paths::script <name> — absolute path of a script under scripts/.
paths::script() { printf '%s/%s' "$HYPR_SCRIPTS" "$1"; }

# ---- user content ---------------------------------------------------------
# Overridable so a machine that keeps wallpapers elsewhere needs no edits.
readonly HYPR_WALLPAPER_DIR="${HYPR_WALLPAPER_DIR:-${HOME}/Pictures/Wallpapers}"
readonly HYPR_WALLPAPER_DEFAULT="${HYPR_WALLPAPER_DEFAULT:-${HYPR_WALLPAPER_DIR}/suf.png}"

# Stable symlinks other tools (hyprlock, hyprpaper) read. They are per-machine
# runtime state and are deliberately not tracked by git.
readonly HYPR_WALLPAPER_LINK="${HYPR_HOME}/current-wallpaper"
readonly HYPR_LOCK_WALLPAPER_LINK="${HYPR_HOME}/lock-wallpaper"
