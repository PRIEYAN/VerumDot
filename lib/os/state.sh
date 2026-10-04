#!/usr/bin/env bash
# os/state.sh — persisted scalar values, with validation at the boundary.
#
# The old scripts each rolled their own version of "read a number out of a
# file in ~/.cache, and if it is garbage pretend it was the default". The
# brightness boost factor had that logic written out twice, in two scripts,
# with two slightly different regexes — so a corrupt state file could be
# accepted by one and rejected by the other.
#
# Here a store is opened once with its default and its validator, and every
# read is guaranteed to return a value that passes the validator.

hypr::use core/log core/paths

# state::get <key> <default> [validator] — read, falling back to the default
# whenever the file is absent, empty, or fails the validator.
#
# <validator> is the name of a function taking the candidate value and
# returning 0 if it is acceptable. Omit it to accept any non-empty value.
state::get() {
  local key=$1 fallback=$2 validator=${3:-} file value
  file="${HYPR_STATE_DIR}/${key}"
  [[ -r $file ]] || { printf '%s' "$fallback"; return 0; }
  value=$(<"$file") || { printf '%s' "$fallback"; return 0; }
  [[ -n $value ]] || { printf '%s' "$fallback"; return 0; }
  if [[ -n $validator ]] && ! "$validator" "$value"; then
    log::warn "state '$key' held an invalid value; using default '$fallback'"
    printf '%s' "$fallback"
    return 0
  fi
  printf '%s' "$value"
}

# state::set <key> <value> — write atomically.
#
# Atomicity is not pedantry here: waybar polls these files on a timer, and a
# plain `echo > file` is a truncate followed by a write. A poll landing in
# that window read an empty file and painted a blank module.
state::set() {
  local key=$1 value=$2 file tmp
  mkdir -p -- "$HYPR_STATE_DIR"
  file="${HYPR_STATE_DIR}/${key}"
  tmp="${file}.$$.tmp"
  printf '%s' "$value" >"$tmp" || return 1
  mv -f -- "$tmp" "$file"
}

# state::clear <key>...
state::clear() {
  local key
  for key in "$@"; do rm -f -- "${HYPR_STATE_DIR}/${key}"; done
}

# state::exists <key> — true if the key holds a non-empty value. Used for
# "has the user ever made this choice?", which is distinct from the value
# itself (the lock screen tracks the desktop wallpaper until, and only
# until, a lock-specific one has been chosen).
state::exists() { [[ -s "${HYPR_STATE_DIR}/${1}" ]]; }

# ---------------------------------------------------------------------------
# Validators
# ---------------------------------------------------------------------------
# Shared so two scripts reading the same key cannot disagree about what a
# valid value looks like.
state::is_number()  { [[ $1 =~ ^[0-9]+(\.[0-9]+)?$ ]]; }
state::is_integer() { [[ $1 =~ ^-?[0-9]+$ ]]; }
state::is_path()    { [[ -e $1 ]]; }

# state::get_enum <key> <default> <allowed>... — the common case where the
# stored value must be one of a fixed set. Keeping it here means the set is
# declared once per concept rather than re-listed at every read site.
state::get_enum() {
  local key=$1 fallback=$2 value candidate
  shift 2
  value=$(state::get "$key" "$fallback")
  for candidate in "$@"; do
    [[ $value == "$candidate" ]] && { printf '%s' "$value"; return 0; }
  done
  printf '%s' "$fallback"
}

# ---------------------------------------------------------------------------
# Latches
# ---------------------------------------------------------------------------
# A latch is a once-only flag: "we have already warned about 15% battery".
# state::latch returns 0 the first time it is called for a name and 1 after,
# until state::unlatch clears it.
state::latch() {
  local file="${HYPR_STATE_DIR}/latch.${1}"
  mkdir -p -- "$HYPR_STATE_DIR"
  [[ -e $file ]] && return 1
  : >"$file"
}

state::unlatch() { rm -f -- "${HYPR_STATE_DIR}/latch.${1}"; }

# state::set_latch <name> — mark a latch as already fired without acting.
# (Crossing 15% implies 20% was crossed too; marking both stops the 20%
# warning from firing on the way back up.)
state::set_latch() {
  mkdir -p -- "$HYPR_STATE_DIR"
  : >"${HYPR_STATE_DIR}/latch.${1}"
}
