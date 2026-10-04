#!/usr/bin/env bash
# domain/fan.sh — hp-wmi fan control (HP Victus and relatives).
#
# The hardware offers two states and no duty cycle:
#
#   pwm1_enable = 2   BIOS automatic curve, whose aggressiveness follows the
#                     ACPI platform profile that ppd sets from the power mode
#   pwm1_enable = 0   both fans pinned at maximum
#
# At idle all three BIOS curves settle at the same RPM, so the power profile
# alone is not an audible fan control — pinning is what you actually hear.
# Hence a three-way setting layered over a two-state device:
#
#   auto    follow the power mode: pin only in performance
#   normal  always the BIOS curve, even in performance
#   max     always pinned, even on battery
#
# The setting persists; the resolved pwm value does not, because
# pwm1_enable returns to the BIOS default on every boot. fan::apply is what
# re-asserts it, at login and after any power-mode change.

# domain/power is a genuine mutual dependency: the fan policy is expressed
# relative to the power mode, and changing the power mode re-resolves the
# fan. The module loader marks a module as loaded before sourcing it, so the
# cycle terminates — the function definitions are all in place before any of
# them is called.
hypr::use core/log core/guard os/proc os/state ui/notify domain/power

readonly -a FAN_MODES=(auto normal max)
readonly FAN_STATE_KEY=fan-mode

readonly FAN_PWM_BIOS=2
readonly FAN_PWM_PINNED=0

# fan::device — the pwm1_enable node of the hp-wmi hwmon.
#
# Matched by driver name, not by a hardcoded hwmon4: the hwmon number is
# assigned at probe time and moves between boots.
fan::device() {
  if [[ -z ${_FAN_DEVICE+set} ]]; then
    local hwmon
    _FAN_DEVICE=""
    for hwmon in /sys/class/hwmon/hwmon*; do
      [[ -r "$hwmon/name" ]] || continue
      [[ $(<"$hwmon/name") == hp ]] || continue
      [[ -e "$hwmon/pwm1_enable" ]] || continue
      _FAN_DEVICE="$hwmon/pwm1_enable"
      break
    done
  fi
  [[ -n $_FAN_DEVICE ]] || return 1
  printf '%s' "$_FAN_DEVICE"
}

fan::supported() { fan::device >/dev/null; }

fan::mode() { state::get_enum "$FAN_STATE_KEY" auto "${FAN_MODES[@]}"; }

# fan::target_pwm — what the current (setting, power mode) pair resolves to.
# This is the whole policy, in one expression.
fan::target_pwm() {
  case "$(fan::mode)" in
    max)    printf '%s' "$FAN_PWM_PINNED" ;;
    normal) printf '%s' "$FAN_PWM_BIOS" ;;
    *)
      if [[ $(power::mode) == performance ]]; then
        printf '%s' "$FAN_PWM_PINNED"
      else
        printf '%s' "$FAN_PWM_BIOS"
      fi
      ;;
  esac
}

# fan::_write <value> — push a pwm value, skipping a no-op write.
#
# Writing the value the node already holds still round-trips through WMI,
# which is slow and occasionally noisy. The redirect is brace-wrapped
# because a failed redirection is reported by the shell itself, not by
# printf, so `printf ... 2>/dev/null` alone still leaks "Permission denied".
fan::_write() {
  local want=$1 device
  device=$(fan::device) || {
    log::error "no hp-wmi fan node — this machine has no supported fan control"
    return 1
  }
  [[ $(proc::capture_or '' cat "$device") == "$want" ]] && return 0
  if { printf '%s' "$want" >"$device"; } 2>/dev/null; then
    return 0
  fi
  log::error "$device is not writable — install apps/udev/99-hp-fan.rules"
  return 1
}

fan::apply() { fan::_write "$(fan::target_pwm)"; }

fan::set_mode() {
  local mode=$1
  guard::one_of "$mode" "${FAN_MODES[@]}" >/dev/null || return 2
  state::set "$FAN_STATE_KEY" "$mode"
  fan::apply || return 1
  local label=$mode
  [[ $mode == auto ]] && label="auto ($(power::mode))"
  notify::transient fan-mode "Fan · ${label}"
}

fan::next_mode() {
  case "$(fan::mode)" in
    auto)   printf 'normal' ;;
    normal) printf 'max' ;;
    *)      printf 'auto' ;;
  esac
}

fan::cycle() { fan::set_mode "$(fan::next_mode)"; }

# fan::rpm — the two fan tachometers, as "front/rear". Zero when unreadable.
fan::rpm() {
  local device dir
  device=$(fan::device) || { printf '0/0'; return 1; }
  dir=${device%/*}
  printf '%s/%s' \
    "$(proc::capture_or 0 cat "$dir/fan1_input")" \
    "$(proc::capture_or 0 cat "$dir/fan2_input")"
}

fan::status() {
  local device
  device=$(fan::device) || { printf 'unsupported\n'; return 1; }
  printf 'setting=%s mode=%s pwm1_enable=%s rpm=%s\n' \
    "$(fan::mode)" "$(power::mode)" \
    "$(proc::capture_or '?' cat "$device")" "$(fan::rpm)"
}
