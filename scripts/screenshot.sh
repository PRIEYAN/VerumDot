#!/usr/bin/env bash
# Screenshots to ~/Pictures/Screenshots, also copied to the clipboard.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/cli core/guard os/proc ui/notify

readonly SHOT_DIR="${HYPR_SCREENSHOT_DIR:-${HOME}/Pictures/Screenshots}"

shot_path() { printf '%s/screenshot-%s.png' "$SHOT_DIR" "$(date +%Y%m%d-%H%M%S)"; }

# finish <file> — the shared tail of every capture mode: copy, then report.
finish() {
  local file=$1
  [[ -s $file ]] || { notify::warn 'Screenshot failed' 'Nothing was captured.'; return 1; }
  guard::has wl-copy && wl-copy <"$file"
  notify::send -i "$file" 'Screenshot saved' "$(basename -- "$file")"
}

cmd_full() {
  guard::require grim
  mkdir -p -- "$SHOT_DIR"
  local file; file=$(shot_path)
  grim "$file" || { notify::warn 'Screenshot failed' 'grim could not capture the screen.'; return 1; }
  finish "$file"
}

cmd_selection() {
  guard::require grim slurp
  mkdir -p -- "$SHOT_DIR"
  local geometry file
  # An empty selection means the user pressed Escape — a normal cancel, not
  # an error, so it must not leave a zero-byte file or fire a notification.
  geometry=$(slurp) || return 0
  [[ -z $geometry ]] && return 0
  file=$(shot_path)
  grim -g "$geometry" "$file" || { notify::warn 'Screenshot failed' 'grim could not capture the region.'; return 1; }
  finish "$file"
}

declare -A COMMANDS=(
  [full]="cmd_full|capture the entire screen (the default)"
  [selection]="cmd_selection|pick a region with slurp"
)

cli::dispatch "${1:-full}" "${@:2}"
