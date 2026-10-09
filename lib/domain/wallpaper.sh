#!/usr/bin/env bash
# domain/wallpaper.sh — desktop and lock-screen wallpapers (separate, independent choices).

hypr::use core/guard core/log core/paths os/proc os/state os/hypr

readonly WALLPAPER_KEY=wallpaper
readonly WALLPAPER_LOCK_KEY=wallpaper-lock
readonly -a WALLPAPER_EXTENSIONS=(jpg jpeg png webp)

# wallpaper::_resolve <path> — the path if it is a usable image, else the
# configured default. Hyprland's own stock wallpaper is explicitly rejected:
# restoring it is never what the user meant, and it is what a stale cache
# from a fresh install points at.
wallpaper::_resolve() {
  local image=$1
  [[ -f $image && $image != /usr/share/hypr/* ]] || image=$HYPR_WALLPAPER_DEFAULT
  printf '%s' "$image"
}

wallpaper::current() {
  wallpaper::_resolve "$(state::get "$WALLPAPER_KEY" "$HYPR_WALLPAPER_DEFAULT")"
}

wallpaper::lock_current() {
  local image
  image=$(state::get "$WALLPAPER_LOCK_KEY" "")
  [[ -n $image && -f $image ]] || image=$(wallpaper::current)
  printf '%s' "$image"
}

# wallpaper::list — every image in the wallpaper directory, sorted.
wallpaper::list() {
  [[ -d $HYPR_WALLPAPER_DIR ]] || return 0
  local -a predicate=()
  local ext
  for ext in "${WALLPAPER_EXTENSIONS[@]}"; do
    (( ${#predicate[@]} )) && predicate+=(-o)
    predicate+=(-iname "*.${ext}")
  done
  find "$HYPR_WALLPAPER_DIR" -maxdepth 1 -type f \( "${predicate[@]}" \) | sort
}

# wallpaper::set <path> — make it the desktop wallpaper.
wallpaper::set() {
  local image; image=$(wallpaper::_resolve "$1")

  state::set "$WALLPAPER_KEY" "$image"
  ln -sfn -- "$image" "$HYPR_WALLPAPER_LINK"

  # The lock screen follows the desktop only until a lock-specific wallpaper
  # has been chosen. Without this test, changing the desktop wallpaper also
  # silently changed a lock screen the user had deliberately pinned.
  state::exists "$WALLPAPER_LOCK_KEY" || ln -sfn -- "$image" "$HYPR_LOCK_WALLPAPER_LINK"

  wallpaper::_push "$image"
}

wallpaper::set_lock() {
  local image; image=$(wallpaper::_resolve "$1")
  # hyprlock reads the file at lock time, so there is no daemon to poke:
  # recording the choice and repointing the symlink is the whole job.
  state::set "$WALLPAPER_LOCK_KEY" "$image"
  ln -sfn -- "$image" "$HYPR_LOCK_WALLPAPER_LINK"
}

# wallpaper::_push <image> — hand it to hyprpaper on every monitor.
#
# hyprpaper 0.8+ unified its IPC: `wallpaper` loads the image itself, and a
# separate `preload` is now rejected as an invalid request.
wallpaper::_push() {
  local image=$1 monitor
  while read -r monitor; do
    [[ -n $monitor ]] && proc::quiet hyprctl hyprpaper wallpaper "${monitor},${image}"
  done < <(hypr::monitors)
}

# wallpaper::init — called once at session start.
wallpaper::init() {
  wallpaper::_ensure_daemon
  wallpaper::set "$(wallpaper::current)"
  # Restore the lock screen's own choice, or point it at the desktop
  # wallpaper, so hyprlock never falls back to a flat colour.
  ln -sfn -- "$(wallpaper::lock_current)" "$HYPR_LOCK_WALLPAPER_LINK"
}

wallpaper::_ensure_daemon() {
  pgrep -x hyprpaper >/dev/null 2>&1 && return 0
  hyprpaper >/dev/null 2>&1 &
  # Wait for the IPC socket rather than sleeping blindly, so the first
  # `wallpaper` call cannot race the daemon's startup.
  hypr::wait_for_socket "$(hypr::hyprpaper_socket)" 50 \
    || log::warn "hyprpaper did not come up in time"
}
