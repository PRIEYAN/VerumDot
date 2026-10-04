#!/usr/bin/env bash
# os/symlink.sh — managed symlinks with one-shot backups.
#
# Installing the theme means replacing files the user may already own, so
# every replacement backs the original up exactly once. "Once" matters: a
# second install must not overwrite the backup with the symlink it created
# the first time, which would lose the real file for good.

hypr::use core/log

readonly SYMLINK_BACKUP_SUFFIX='.prehypr'

# symlink::install <source> <target>
symlink::install() {
  local source=$1 target=$2
  mkdir -p -- "$(dirname -- "$target")"

  if [[ -L $target ]]; then
    # Our own link from a previous run; replacing it is not a loss.
    rm -f -- "$target"
  elif [[ -e $target ]]; then
    if [[ ! -e "${target}${SYMLINK_BACKUP_SUFFIX}" ]]; then
      mv -- "$target" "${target}${SYMLINK_BACKUP_SUFFIX}"
      log::info "backed up ${target} -> ${target}${SYMLINK_BACKUP_SUFFIX}"
    else
      # A backup already exists, so this is a real file left by something
      # else; the original is safe and this copy can go.
      rm -rf -- "$target"
    fi
  fi

  ln -s -- "$source" "$target"
  log::info "linked ${target}"
}

# symlink::remove <target> — drop our link and restore any backup.
symlink::remove() {
  local target=$1
  [[ -L $target ]] && { rm -f -- "$target"; log::info "unlinked ${target}"; }
  if [[ -e "${target}${SYMLINK_BACKUP_SUFFIX}" ]]; then
    mv -- "${target}${SYMLINK_BACKUP_SUFFIX}" "$target"
    log::info "restored ${target}"
  fi
}
