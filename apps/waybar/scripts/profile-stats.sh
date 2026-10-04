#!/usr/bin/env bash
# Stats for the profile dropdown, as plain "key percent label unit" lines.
#
# The caller stays ignorant of how each number was computed, which is why
# this stays a line protocol rather than returning JSON: profile-menu.sh
# reads it with a bare `while read`.
#
# Deliberately *not* domain/sysstats: this wants a cheap one-shot sample
# with a hottest-sensor temperature, where the control centre's table wants
# cached rate counters and per-engine GPU detail. Sharing the sampler would
# mean one of the two callers paying for work it does not use.

# --- library bootstrap -----------------------------------------------------
# Identical in every executable regardless of its depth: walk up until lib/
# is found, then hand over. See lib/bootstrap.sh.
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
# shellcheck source=/dev/null
source "$_dir/lib/bootstrap.sh"
unset _dir
hypr::use core/guard os/proc

readonly CPU_SAMPLE_SECONDS=0.1
readonly TEMP_SANITY_CEILING=200   # °C; see the sensors note below

percent() { awk -v u="$1" -v t="$2" 'BEGIN { printf "%d", (t > 0) ? (100 * u / t) + 0.5 : 0 }'; }
gibibytes() { awk -v k="$1" 'BEGIN { printf "%.1f", k / 1048576 }'; }

# CPU: sample /proc/stat twice and diff the busy fraction.
cpu_percent() {
  local -a before after
  read -r _ before[0] before[1] before[2] before[3] before[4] before[5] before[6] before[7] _ </proc/stat
  sleep "$CPU_SAMPLE_SECONDS"
  read -r _ after[0] after[1] after[2] after[3] after[4] after[5] after[6] after[7] _ </proc/stat
  awk -v a="${before[*]}" -v b="${after[*]}" 'BEGIN {
    n = split(a, x, " "); split(b, y, " ")
    for (i = 1; i <= n; i++) { ta += x[i]; tb += y[i] }
    ia = x[4] + x[5]; ib = y[4] + y[5]          # idle + iowait
    dt = tb - ta; di = ib - ia
    printf "%d", (dt > 0) ? (100 * (dt - di) / dt) + 0.5 : 0
  }'
}

read -r mem_total mem_avail swap_total swap_free < <(awk '
  /^MemTotal:/     { mt = $2 }
  /^MemAvailable:/ { ma = $2 }
  /^SwapTotal:/    { st = $2 }
  /^SwapFree:/     { sf = $2 }
  END { print mt, ma, st, sf }' /proc/meminfo)

mem_used=$(( mem_total - mem_avail ))
swap_used=$(( swap_total - swap_free ))

cpu=$(cpu_percent)
printf 'CPU %s %s%% cpu\n' "$cpu" "$cpu"
printf 'RAM %s %sG/%sG ram\n' "$(percent "$mem_used" "$mem_total")" \
  "$(gibibytes "$mem_used")" "$(gibibytes "$mem_total")"

# GPU is optional — emitted only when nvidia-smi actually answers.
if guard::has nvidia-smi; then
  gpu=$(proc::capture nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits \
        | awk 'NR == 1 { printf "%d", $1 + 0.5 }')
  [[ -n $gpu ]] && printf 'GPU %s %s%% gpu\n' "$gpu" "$gpu"
fi

if (( ${swap_total:-0} > 0 )); then
  printf 'SWAP %s %sG/%sG swap\n' "$(percent "$swap_used" "$swap_total")" \
    "$(gibibytes "$swap_used")" "$(gibibytes "$swap_total")"
fi

# Hottest sensor wins. Only the first reading on each line is the actual
# temperature — the parenthesised values are low/high/crit thresholds, and
# some NVMe drives report a bogus "high = +65261.8°C" that would otherwise
# take the maximum. Hence both the paren strip and the sanity ceiling.
if guard::has sensors; then
  temp=$(sensors -A 2>/dev/null \
    | sed 's/(.*//' \
    | grep -oP '\+\K[0-9.]+(?=\s*°C)' \
    | awk -v ceiling="$TEMP_SANITY_CEILING" \
        'BEGIN { m = -1 } { v = $1 + 0; if (v > m && v < ceiling) m = v } END { if (m >= 0) printf "%d", m + 0.5 }')
  [[ -n $temp ]] && printf 'TEMP %s %s°C temp\n' "$temp" "$temp"
fi
