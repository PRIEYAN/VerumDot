#!/usr/bin/env bash
# core/migrate.sh — move pre-refactor state into os/state's keyspace.
#
# Before the refactor each script invented its own location: two files in
# ~/.cache with a `hypr_` name prefix, one in world-writable /tmp under a
# fixed name, one already in the right place. os/state owns all of them now,
# so the first run after upgrading has to carry the user's existing choices
# across — losing a pinned lock-screen wallpaper or a chosen fan mode on
# upgrade is not acceptable.
#
# Runs once, guarded by a marker, and is idempotent regardless.

hypr::use core/log core/paths os/state

readonly MIGRATE_MARKER="${HYPR_STATE_DIR}/.migrated-v1"

# old path -> new state key
declare -Ag _MIGRATE_MAP=(
  ["${XDG_CACHE_HOME}/hypr_wallpaper"]=wallpaper
  ["${XDG_CACHE_HOME}/hypr_lock_wallpaper"]=wallpaper-lock
  ["${XDG_CACHE_HOME}/hypr_brightness_boost"]=brightness-boost
  ["/tmp/waybar-performance-mode"]=power-mode
)

migrate::run() {
  [[ -e $MIGRATE_MARKER ]] && return 0
  mkdir -p -- "$HYPR_STATE_DIR"

  local old key value moved=0
  for old in "${!_MIGRATE_MAP[@]}"; do
    key=${_MIGRATE_MAP[$old]}
    # Never overwrite a value the new code has already written.
    state::exists "$key" && continue
    [[ -s $old ]] || continue
    value=$(<"$old")
    # Stored values carried a trailing newline from `echo`; os/state does not.
    state::set "$key" "${value%$'\n'}"
    log::info "migrated ${old} -> state/${key}"
    (( moved++ ))
  done

  : >"$MIGRATE_MARKER"
  (( moved )) && log::info "migrated ${moved} setting(s) into ${HYPR_STATE_DIR}"
  return 0
}
