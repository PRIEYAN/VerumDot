#!/usr/bin/env bash
# Battery module for waybar, plus the system-stats dropdown behind it.
#
#   (no args)  emit the waybar module JSON — glyph and capacity
#   menu       open the stats panel under the battery (click again to close)
#   rows       rofi script-mode backend; rofi re-execs this on every
#              activation key, which is how the panel refreshes in place
#
# The class (mode-performance / mode-battery / mode-normal) is what
# style.css uses to tint the glyph red / green / white.
#
# The sampling lives in lib/domain/sysstats.sh and the rendering in
# lib/ui/table.sh, so this file is only the three output shapes.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/cli core/migrate ui/rofi ui/rofi_script ui/table ui/waybar \
          domain/battery domain/sysstats domain/power

migrate::run

declare -Ag MODE_LABEL=([normal]='Balanced' [performance]='Performance' [battery]='Battery saver')

# battery::_headline — the panel's prompt line, in plain text and markup.
# Sets HEAD_PLAIN and HEAD_MARKUP.
read_headline() {
  local mode capacity status health icon bolt
  mode=$(power::mode)
  local label=${MODE_LABEL[$mode]:-Balanced}

  if battery::present; then
    capacity=$(battery::capacity)
    status=$(battery::status)
    health=$(battery::health)
    icon=$(battery::icon "$capacity")
    battery::charging && bolt="${BATTERY_BOLT} " || bolt=''

    BAR_TEXT="${bolt}${icon} ${capacity}%"
    HEAD_PLAIN="${icon} ${capacity}%  ·  ${status} · ${label} · health ${health}"
    HEAD_MARKUP=$(printf '<span size="large">%s %s%%</span>  %s' \
      "$icon" "$capacity" "$(table::dim "${status} · ${label} · health ${health}")")
  else
    BAR_TEXT="${BATTERY_AC_ICON} AC"
    HEAD_PLAIN="${BATTERY_AC_ICON} AC  ·  ${label}"
    HEAD_MARKUP=$(printf '<span size="large">%s AC</span>  %s' \
      "$BATTERY_AC_ICON" "$(table::dim "No battery · ${label}")")
  fi
  BAR_CLASS="mode-${mode}"
}

# The table, one markup row per line. Declared as a list of (label, value,
# tail) so adding a sensor is a line rather than another printf.
stat_rows() {
  table::row CPU  "$SYS_CPU_PCT"  "$(table::temp_cell "$SYS_PKG_TEMP")"
  table::row RAM  "$SYS_MEM_PCT"  "$(table::dim "${SYS_MEM_USED}/${SYS_MEM_TOTAL}G")"
  table::row SWAP "$SYS_SWAP_PCT" "$(table::dim "${SYS_SWAP_USED}/${SYS_SWAP_TOTAL}G")"
  table::row GPU0 "$SYS_IGPU_PCT" "$(table::temp_cell "$SYS_PKG_TEMP") $(table::dim 'Intel UHD')"
  if (( SYS_NV_PRESENT )); then
    local tail='RTX 3050'
    [[ -n $SYS_NV_NOTE ]] && tail+=" · ${SYS_NV_NOTE}"
    table::row GPU1 "$SYS_NV_PCT" "$(table::temp_cell "$SYS_NV_TEMP") $(table::dim "$tail")"
  fi
}

# Bar module. Deliberately skips sysstats::collect entirely — the stats live
# in the dropdown, so the 5s poll pays for no /proc/*/fdinfo walk and no
# nvidia-smi, and leaves the rate-counter baseline for the panel to sample.
cmd_status() {
  read_headline
  waybar::emit "$BAR_TEXT" "" "$BAR_CLASS"
}

cmd_rows() {
  sysstats::collect
  read_headline
  # The header is re-emitted on every repaint so the battery line stays
  # current too, not just the table.
  rofi_script::header "$HEAD_PLAIN"
  # Rows stay activatable even though nothing opens: a non-selectable row
  # cannot be activated, which would make Return a no-op and kill the
  # refresh. The theme suppresses the highlight instead, so it still reads
  # as a table rather than a menu.
  stat_rows
}

cmd_menu() {
  # Esc closes via rofi's untouched kb-cancel. 'r' and space are wired to the
  # same re-render as Return, so any of them refreshes in place.
  rofi::toggle sysstats || exit 0
  exec rofi -show stats -modi "stats:$(readlink -f -- "${BASH_SOURCE[0]}") rows" \
    -theme "$(rofi::theme_path sysstats)" \
    -kb-accept-entry 'Return,KP_Enter,r,space'
}

declare -A COMMANDS=(
  [status]="cmd_status|emit the waybar module JSON (the default)"
  [menu]="cmd_menu|open the system stats panel"
  [rows]="cmd_rows|rofi script-mode backend (not for direct use)"
)

cli::dispatch "${1:-status}" "${@:2}"
