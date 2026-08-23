#!/usr/bin/env bash
# Gathers CPU / RAM / GPU / SWAP / TEMP for the profile dropdown.
# Printed as plain "key pct label unit" lines so the caller stays ignorant
# of how each number was computed.

# CPU: sample /proc/stat twice and diff the busy fraction.
read -r _ a0 a1 a2 a3 a4 a5 a6 a7 _ < /proc/stat
sleep 0.1
read -r _ b0 b1 b2 b3 b4 b5 b6 b7 _ < /proc/stat
cpu=$(awk -v a0=$a0 -v a1=$a1 -v a2=$a2 -v a3=$a3 -v a4=$a4 -v a5=$a5 -v a6=$a6 -v a7=$a7 \
          -v b0=$b0 -v b1=$b1 -v b2=$b2 -v b3=$b3 -v b4=$b4 -v b5=$b5 -v b6=$b6 -v b7=$b7 'BEGIN{
  ta=a0+a1+a2+a3+a4+a5+a6+a7; tb=b0+b1+b2+b3+b4+b5+b6+b7
  ia=a3+a4; ib=b3+b4
  dt=tb-ta; di=ib-ia
  printf "%d", (dt>0) ? (100*(dt-di)/dt)+0.5 : 0
}')

# Memory and swap, in kB, straight from meminfo.
mem_total=$(awk '/^MemTotal:/{print $2}'  /proc/meminfo)
mem_avail=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
swap_total=$(awk '/^SwapTotal:/{print $2}' /proc/meminfo)
swap_free=$(awk '/^SwapFree:/{print $2}'  /proc/meminfo)
mem_used=$(( mem_total - mem_avail ))
swap_used=$(( swap_total - swap_free ))

pct()  { awk -v u="$1" -v t="$2" 'BEGIN{printf "%d", (t>0) ? (100*u/t)+0.5 : 0}'; }
gib()  { awk -v k="$1" 'BEGIN{printf "%.1f", k/1048576}'; }

ram_pct=$(pct "$mem_used" "$mem_total")
printf 'CPU %s %s%% cpu\n' "$cpu" "$cpu"
printf 'RAM %s %sG/%sG ram\n' "$ram_pct" "$(gib "$mem_used")" "$(gib "$mem_total")"

# GPU is optional -- only emitted when nvidia-smi answers.
if command -v nvidia-smi >/dev/null 2>&1; then
  gpu=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null \
        | awk 'NR==1{printf "%d", $1+0.5}')
  [ -n "$gpu" ] && printf 'GPU %s %s%% gpu\n' "$gpu" "$gpu"
fi

if [ "${swap_total:-0}" -gt 0 ]; then
  printf 'SWAP %s %sG/%sG swap\n' "$(pct "$swap_used" "$swap_total")" \
    "$(gib "$swap_used")" "$(gib "$swap_total")"
fi

# Hottest sensor reading wins, matching the old behaviour.
if command -v sensors >/dev/null 2>&1; then
  # Only the first reading on each line is the actual temperature; the values
  # in parentheses are low/high/crit thresholds. Some NVMe drives report a
  # bogus "high = +65261.8°C", which would otherwise win the max.
  temp=$(sensors -A 2>/dev/null \
    | sed 's/(.*//' \
    | grep -oP '\+\K[0-9.]+(?=\s*°C)' \
    | awk 'BEGIN{m=-1} {v=$1+0; if(v>m && v<200) m=v} END{if(m>=0) printf "%d", m+0.5}')
  [ -n "$temp" ] && printf 'TEMP %s %s°C temp\n' "$temp" "$temp"
fi
