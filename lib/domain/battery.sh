#!/usr/bin/env bash
# domain/battery.sh — the battery, as read from sysfs.

hypr::use core/guard os/proc os/state ui/notify

# battery::path — the first battery that actually reports a capacity.
# Cached: this is read in a 30-second loop and the answer cannot change.
battery::path() {
  if [[ -z ${_BATTERY_PATH+set} ]]; then
    local dir
    _BATTERY_PATH=""
    for dir in /sys/class/power_supply/BAT*; do
      [[ -r "$dir/capacity" ]] && { _BATTERY_PATH=$dir; break; }
    done
  fi
  [[ -n $_BATTERY_PATH ]] || return 1
  printf '%s' "$_BATTERY_PATH"
}

battery::present() { battery::path >/dev/null; }

battery::capacity() {
  local p; p=$(battery::path) || { printf '100'; return 1; }
  proc::capture_or 100 cat "$p/capacity"
}

battery::status() {
  local p; p=$(battery::path) || { printf 'Unknown'; return 1; }
  proc::capture_or Unknown cat "$p/status"
}

# battery::charging — "is the battery being topped up or held full?".
# "Not charging" means plugged in but deliberately not charging (a charge
# limit), which is still mains power and must not trigger a low warning.
battery::charging() {
  case "$(battery::status)" in
    Charging|Full|"Not charging") return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Low-battery warnings
# ---------------------------------------------------------------------------
# Thresholds are declared as data, most severe first, so adding one is a line
# here rather than another branch in the watcher loop.
readonly -a BATTERY_THRESHOLDS=(15 20)
declare -Ag BATTERY_WARNING=(
  [15]="Battery critical|Plug in now — the system will suspend shortly.|critical"
  [20]="Battery low|Running on reserve. Time to find a charger.|critical"
)

# battery::check_thresholds <capacity> — fire at most one warning, for the
# most severe threshold crossed, and arm the quieter ones so they do not
# also fire on the way down.
battery::check_thresholds() {
  local capacity=$1 level fired=0 title body urgency
  for level in "${BATTERY_THRESHOLDS[@]}"; do
    if (( capacity <= level )); then
      if (( ! fired )); then
        IFS='|' read -r title body urgency <<<"${BATTERY_WARNING[$level]}"
        if state::latch "battery-$level"; then
          notify::send -u "$urgency" -i battery-caution -r battery-low \
            "${title} — ${capacity}%" "$body"
        fi
        fired=1
      else
        # Crossing 15% implies 20% was crossed; arm it silently so it does
        # not fire as a second, redundant toast.
        state::set_latch "battery-$level"
      fi
    fi
  done
}

# battery::clear_warnings — re-arm every threshold, called when AC returns
# or the charge climbs back above the band.
battery::clear_warnings() {
  local level
  for level in "${BATTERY_THRESHOLDS[@]}"; do state::unlatch "battery-$level"; done
}

# battery::reset_above <capacity> — re-arm only the thresholds the charge has
# genuinely risen above, so a battery hovering at 16% does not re-alert.
battery::reset_above() {
  local capacity=$1 level
  for level in "${BATTERY_THRESHOLDS[@]}"; do
    (( capacity > level )) && state::unlatch "battery-$level"
  done
}

# ---------------------------------------------------------------------------
# Presentation inputs
# ---------------------------------------------------------------------------
# Glyphs are built from codepoints rather than pasted in: these are Nerd Font
# private-use characters, which do not survive every editor and pipeline
# round-trip, and a silently emptied glyph is invisible to review.
#
# Declared most-charged first, so the lookup is a walk rather than a chain of
# elif branches with hand-maintained boundaries.
readonly -a BATTERY_ICON_STEPS=(80 40 15 0)
declare -Ag BATTERY_ICON=(
  [80]=$'\U000F0240'   # nf-md-battery_high
  [40]=$'\U000F0241'   # nf-md-battery_medium
  [15]=$'\U000F0242'   # nf-md-battery_low
  [0]=$'\U000F0243'    # nf-md-battery_outline
)
readonly BATTERY_AC_ICON=$'\U000F01E6'   # nf-md-power_plug
readonly BATTERY_BOLT=$'\uF0E7'          # nf-fa-bolt

# battery::icon <capacity> — the glyph for a charge level.
battery::icon() {
  local capacity=$1 step
  for step in "${BATTERY_ICON_STEPS[@]}"; do
    (( capacity > step )) && { printf '%s' "${BATTERY_ICON[$step]}"; return 0; }
  done
  printf '%s' "${BATTERY_ICON[0]}"
}

# battery::health — remaining full-charge capacity against the factory
# design capacity, i.e. how much of the original battery is left.
#
# upower reports it directly and cheaply (~13ms). The sysfs arithmetic is
# the identical number, kept for machines without upower installed.
battery::health() {
  local path device pct=''
  if guard::has upower; then
    device=$(upower -e 2>/dev/null | grep -m1 BAT)
    [[ -n $device ]] && pct=$(upower -i "$device" 2>/dev/null | awk '/capacity:/ { print $2 }')
  fi
  if [[ -z $pct ]] && path=$(battery::path); then
    pct=$(awk -v f="$(proc::capture_or 0 cat "$path/energy_full")" \
              -v d="$(proc::capture_or 0 cat "$path/energy_full_design")" \
              'BEGIN { if (d + 0 > 0) print f / d * 100 }')
  fi
  pct=${pct%\%}
  [[ -n $pct ]] && printf '%.0f%%' "$pct" || printf 'n/a'
}
