#!/usr/bin/env bash
# Shared Eye Comfort control for Waybar and the control centre.
# Usage: eye-comfort-toggle.sh [toggle | status | apply on|off intensity]
# Hyprsunset supplies the warm tint through Hyprland on Wayland.

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
state_file="$state_dir/eye-comfort-intensity"
intensity=70
if [ -r "$state_file" ]; then
  read -r saved < "$state_file"
  if [[ "$saved" =~ ^[0-9]{1,3}$ ]] && (( 10#$saved <= 100 )); then
    intensity=$((10#$saved))
  fi
fi

read_state() {
  enabled=false
  temperature=$((6500 - intensity * 50))
  local process
  while IFS= read -r process; do
    if [[ "$process" =~ (--temperature|-t)[[:space:]]+([0-9]+) ]]; then
      temperature=${BASH_REMATCH[2]}
      intensity=$(((6500 - temperature) / 50))
      (( intensity < 0 )) && intensity=0
      (( intensity > 100 )) && intensity=100
      enabled=true
      break
    fi
  done < <(pgrep -ax hyprsunset 2>/dev/null)
}

notify() {
  command -v notify-send >/dev/null 2>&1 &&
    notify-send -a "Eye Comfort" \
      -h string:x-canonical-private-synchronous:eye-comfort \
      "$1" "$2" 2>/dev/null || true
}

available=false
command -v hyprsunset >/dev/null 2>&1 && available=true
read_state
mode=${1:-toggle}
if [ "$mode" = status ]; then
  printf '{"enabled":%s,"intensity":%d,"available":%s}\n' \
    "$enabled" "$intensity" "$available"
  exit 0
fi

case "$mode" in
  toggle)
    if [ "$enabled" = true ]; then desired=off; else desired=on; fi ;;
  apply)
    desired=${2:-}
    requested=${3:-}
    if [[ ! "$requested" =~ ^[0-9]{1,3}$ ]] || (( 10#$requested > 100 )); then
      echo 'Intensity must be between 0 and 100' >&2
      exit 2
    fi
    intensity=$((10#$requested)) ;;
  *) echo 'Usage: eye-comfort-toggle.sh [toggle | status | apply on|off intensity]' >&2; exit 2 ;;
esac
case "$desired" in on|off) ;; *) exit 2 ;; esac
if [ "$available" != true ]; then
  [ "$mode" = toggle ] && notify "Eye Comfort" "hyprsunset is not installed"
  echo 'hyprsunset is not installed' >&2
  exit 1
fi

# Serialize the bar toggle and slider writes so only one daemon is launched.
mkdir -p "$state_dir" || exit 1
exec 9>"$state_dir/eye-comfort.lock"
flock -x 9 || exit 1
pkill -x hyprsunset 2>/dev/null || true
for ((attempt=0; attempt<20; attempt++)); do
  pgrep -x hyprsunset >/dev/null || break
  sleep 0.05
done
if pgrep -x hyprsunset >/dev/null; then
  echo 'Could not stop the previous eye comfort process' >&2
  exit 1
fi
if [ "$desired" = on ]; then
  temperature=$((6500 - intensity * 50))
  # Do not let the detached daemon inherit the operation lock.
  setsid -f hyprsunset -t "$temperature" 9>&- >/dev/null 2>&1
  sleep 0.1
  if ! pgrep -x hyprsunset >/dev/null; then
    echo 'Could not start eye comfort' >&2
    exit 1
  fi
fi
printf '%s\n' "$intensity" > "$state_file"
pkill -RTMIN+1 waybar 2>/dev/null || true
if [ "$mode" = toggle ]; then
  if [ "$desired" = on ]; then
    notify "Eye Comfort" "Warm tint (${temperature}K)"
  else
    notify "Eye Comfort Off" "Normal color temperature"
  fi
fi
