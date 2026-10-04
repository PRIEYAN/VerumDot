#!/usr/bin/env bash
# ui/table.sh — the system-stats table, as markup rows.
#
# Pure presentation: every function takes numbers and returns markup, so the
# layout can be exercised without sampling any hardware.

hypr::use ui/markup ui/theme

readonly TABLE_METER_CELLS=10

# table::meter <percent> — a ten-cell block meter. An unknown reading draws
# a dotted rule rather than an empty bar, so "no data" cannot be misread as
# "idle".
table::meter() {
  local pct=${1:-} filled
  if [[ -z $pct ]]; then
    markup::span "$(markup::repeat '·' "$TABLE_METER_CELLS")" "$THEME_DIM"
    return 0
  fi
  pct=$(markup::clamp "$pct" 0 100)
  # Rounded, not truncated: at 10 cells a truncating divide shows an empty
  # bar for anything under 10%, which reads as broken.
  filled=$(( (pct * TABLE_METER_CELLS + 50) / 100 ))
  printf '%s%s' \
    "$(markup::span "$(markup::repeat '█' "$filled")" "$(theme::load_color "$pct")")" \
    "$(markup::span "$(markup::repeat '░' "$(( TABLE_METER_CELLS - filled ))")" "$THEME_DIM")"
}

# table::temp_cell <celsius> — a right-aligned temperature, coloured.
table::temp_cell() {
  local temp=${1:-}
  [[ -z $temp ]] && { markup::span '   --' "$THEME_DIM"; return 0; }
  printf '<span color="%s">%3d°C</span>' "$(theme::temp_color "$temp")" "$temp"
}

table::dim() { markup::span "$1" "$THEME_DIM"; }

# table::row <label> <percent> <trailing-cell> — one line of the table.
table::row() {
  local label=$1 pct=${2:-} tail=${3:-} shown='  --'
  [[ -n $pct ]] && printf -v shown '%4d' "$pct"
  printf '<span color="%s">%-5s</span> %s <span color="%s">%s%%</span>  %s\n' \
    "$THEME_DIM" "$label" "$(table::meter "$pct")" \
    "$(theme::load_color "$pct")" "$shown" "$tail"
}
