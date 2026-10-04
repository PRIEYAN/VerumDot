#!/usr/bin/env bash
# domain/eyecomfort.sh — the warm-tint filter, via hyprsunset.
#
# hyprsunset has no IPC: the only way to change the temperature is to stop
# the running daemon and start a new one. That makes every change a
# read-modify-write across a process, which has to be serialised — the bar
# toggle and the control centre's intensity slider can otherwise race and
# leave two daemons running, each fighting the other's gamma ramp.
#
# The current state is read back from the running process's command line
# rather than from the state file, because the daemon is the truth: if it
# died, the filter is off no matter what the file says. The state file only
# remembers the *chosen intensity* for next time.

hypr::use core/guard core/log core/paths os/proc os/state ui/notify ui/waybar

readonly EYECOMFORT_KEY=eye-comfort-intensity
readonly EYECOMFORT_DEFAULT_INTENSITY=70
readonly EYECOMFORT_BASE_KELVIN=6500
readonly EYECOMFORT_KELVIN_PER_STEP=50
readonly EYECOMFORT_LOCK=eye-comfort

eyecomfort::available() { guard::has hyprsunset; }

# eyecomfort::_valid_intensity <value> — 0..100, written so a leading zero
# is not read as octal (10#).
eyecomfort::_valid_intensity() {
  [[ $1 =~ ^[0-9]{1,3}$ ]] && (( 10#$1 <= 100 ))
}

eyecomfort::temperature_for() {
  printf '%s' $(( EYECOMFORT_BASE_KELVIN - $1 * EYECOMFORT_KELVIN_PER_STEP ))
}

eyecomfort::intensity_for() {
  local intensity=$(( (EYECOMFORT_BASE_KELVIN - $1) / EYECOMFORT_KELVIN_PER_STEP ))
  (( intensity < 0 )) && intensity=0
  (( intensity > 100 )) && intensity=100
  printf '%s' "$intensity"
}

# eyecomfort::active — is a tinted daemon actually running?
# Matched on the argument list, since a bare `hyprsunset` with no -t is not
# applying a tint.
eyecomfort::active() {
  local process
  while IFS= read -r process; do
    [[ $process =~ (--temperature|-t)[[:space:]]+([0-9]+) ]] && return 0
  done < <(pgrep -ax hyprsunset 2>/dev/null)
  return 1
}

# eyecomfort::current_intensity — from the running daemon if there is one,
# otherwise the remembered choice.
eyecomfort::current_intensity() {
  local process
  while IFS= read -r process; do
    if [[ $process =~ (--temperature|-t)[[:space:]]+([0-9]+) ]]; then
      eyecomfort::intensity_for "${BASH_REMATCH[2]}"
      return 0
    fi
  done < <(pgrep -ax hyprsunset 2>/dev/null)
  state::get "$EYECOMFORT_KEY" "$EYECOMFORT_DEFAULT_INTENSITY" eyecomfort::_valid_intensity
}

# eyecomfort::status_json — the shape the control centre reads.
eyecomfort::status_json() {
  jq -nc \
    --argjson enabled "$(eyecomfort::active && echo true || echo false)" \
    --argjson intensity "$(eyecomfort::current_intensity)" \
    --argjson available "$(eyecomfort::available && echo true || echo false)" \
    '{enabled: $enabled, intensity: $intensity, available: $available}'
}

# eyecomfort::_stop — stop the daemon and wait for it to actually be gone.
# Starting the replacement before the old one exits leaves two processes
# fighting over the gamma ramp.
eyecomfort::_stop() {
  pkill -x hyprsunset 2>/dev/null || true
  local attempt
  for (( attempt = 0; attempt < 20; attempt++ )); do
    pgrep -x hyprsunset >/dev/null || return 0
    sleep 0.05
  done
  pgrep -x hyprsunset >/dev/null && return 1
  return 0
}

# eyecomfort::apply <on|off> [intensity] — the single mutator.
eyecomfort::apply() {
  local desired=$1 intensity=${2:-}

  if [[ -n $intensity ]]; then
    eyecomfort::_valid_intensity "$intensity" \
      || { log::error 'intensity must be between 0 and 100'; return 2; }
    intensity=$(( 10#$intensity ))
  else
    intensity=$(eyecomfort::current_intensity)
  fi

  eyecomfort::available || { log::error 'hyprsunset is not installed'; return 1; }

  # Serialise the bar toggle against the slider so only one daemon is ever
  # launched. Held for the rest of this process.
  proc::lock "$EYECOMFORT_LOCK" || { log::error 'another eye-comfort change is in flight'; return 1; }

  eyecomfort::_stop || { log::error 'could not stop the previous eye comfort process'; return 1; }

  if [[ $desired == on ]]; then
    local kelvin; kelvin=$(eyecomfort::temperature_for "$intensity")
    # 9>&- so the detached daemon does not inherit the operation lock and
    # keep it held for its entire lifetime.
    setsid -f hyprsunset -t "$kelvin" 9>&- >/dev/null 2>&1
    sleep 0.1
    pgrep -x hyprsunset >/dev/null || { log::error 'could not start eye comfort'; return 1; }
  fi

  state::set "$EYECOMFORT_KEY" "$intensity"
  waybar::refresh brightness
  return 0
}

eyecomfort::toggle() {
  local desired kelvin
  eyecomfort::active && desired=off || desired=on

  if ! eyecomfort::available; then
    notify::transient eye-comfort 'Eye Comfort' 'hyprsunset is not installed'
    log::error 'hyprsunset is not installed'
    return 1
  fi

  eyecomfort::apply "$desired" || return 1

  if [[ $desired == on ]]; then
    kelvin=$(eyecomfort::temperature_for "$(eyecomfort::current_intensity)")
    notify::transient eye-comfort 'Eye Comfort' "Warm tint (${kelvin}K)"
  else
    notify::transient eye-comfort 'Eye Comfort Off' 'Normal colour temperature'
  fi
}
