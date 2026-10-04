#!/usr/bin/env bash
# domain/brightness.sh — screen brightness as one model.
#
# The hardware backlight and the software shader boost are a single logical
# scale with the hardware below and the shader above:
#
#     10% ......... 100% | 1.00x ......... 2.00x
#      hardware (brightnessctl)   shader (decoration:screen_shader)
#
# Going up past hardware maximum starts boosting; coming down from a boost
# unwinds the shader before touching the backlight again. The old script
# expressed that as a branching tree in brightness_control.sh and then
# *restated* the shader-active test, with a different regex, in
# brightness-status.sh — so the bar and the control could disagree about
# whether a boost was on.

hypr::use core/log core/guard core/paths os/proc os/state os/hypr

readonly BRIGHTNESS_STATE_KEY=brightness-boost
readonly BRIGHTNESS_MIN_PERCENT=10
readonly BRIGHTNESS_STEP_PERCENT=5
readonly BRIGHTNESS_BOOST_MIN=1.0
readonly BRIGHTNESS_BOOST_MAX=2.0
readonly BRIGHTNESS_BOOST_STEP=0.05
readonly BRIGHTNESS_SHADER="${HYPR_SHADERS}/active_boost.glsl"

brightness::available() { guard::has brightnessctl; }

# ---- hardware -------------------------------------------------------------
brightness::hardware_percent() {
  local current max
  brightness::available || { printf '100'; return 1; }
  current=$(proc::capture brightnessctl get) || { printf '100'; return 1; }
  max=$(proc::capture brightnessctl max)     || { printf '100'; return 1; }
  [[ $max =~ ^[0-9]+$ && $max -gt 0 ]] || { printf '100'; return 1; }
  printf '%s' $(( current * 100 / max ))
}

brightness::set_hardware() {
  brightness::available || return 1
  proc::quiet brightnessctl set "$1"
}

# ---- software boost -------------------------------------------------------
# The single reader for the boost factor. Everything that wants to know
# whether a boost is active asks here.
brightness::boost() {
  state::get "$BRIGHTNESS_STATE_KEY" "$BRIGHTNESS_BOOST_MIN" state::is_number
}

brightness::boosted() {
  awk -v b="$(brightness::boost)" -v m="$BRIGHTNESS_BOOST_MIN" 'BEGIN { exit !(b > m) }'
}

# brightness::boost_percent — the boost expressed the way the bar shows it
# (1.25 -> 125).
brightness::boost_percent() {
  awk -v b="$(brightness::boost)" 'BEGIN { printf "%d", b * 100 }'
}

# brightness::_write_shader <factor> — render and install the boost shader.
#
# Written to a temporary file and moved into place: Hyprland may read the
# shader while it is being rewritten, and a half-written GLSL file is a
# compile error that blanks the screen.
brightness::_write_shader() {
  local factor=$1 tmp="${BRIGHTNESS_SHADER}.tmp"
  mkdir -p -- "$HYPR_SHADERS"
  # Vector-vector arithmetic throughout: the GLSL ES compiler rejects the
  # implicit vec3*float conversion that the obvious spelling would use.
  cat >"$tmp" <<GLSL
#version 300 es
precision mediump float;
in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;
uniform sampler2D tex;
void main() {
    vec4 pixColor = texture(tex, v_texcoord);
    vec3 factor = vec3(float(${factor}));
    pixColor.rgb = clamp(pixColor.rgb * factor, vec3(0.0), vec3(1.0));
    fragColor = pixColor;
}
GLSL
  mv -f -- "$tmp" "$BRIGHTNESS_SHADER"
}

# brightness::_apply_boost <factor> — persist the factor and make it visible,
# clearing the shader entirely at 1.0 rather than installing an identity pass.
brightness::_apply_boost() {
  local factor
  factor=$(awk -v v="$1" -v lo="$BRIGHTNESS_BOOST_MIN" -v hi="$BRIGHTNESS_BOOST_MAX" \
    'BEGIN { if (v < lo) v = lo; if (v > hi) v = hi; printf "%.2f", v }')
  state::set "$BRIGHTNESS_STATE_KEY" "$factor"
  if awk -v b="$factor" -v m="$BRIGHTNESS_BOOST_MIN" 'BEGIN { exit !(b <= m) }'; then
    hypr::clear_shader
  else
    brightness::_write_shader "$factor"
    hypr::set_shader "$BRIGHTNESS_SHADER"
  fi
  printf '%s' "$factor"
}

# ---- the combined scale ---------------------------------------------------
brightness::up() {
  if (( $(brightness::hardware_percent) < 100 )); then
    brightness::set_hardware "+${BRIGHTNESS_STEP_PERCENT}%"
    # Leaving a stale boost on while the backlight still has headroom would
    # double-brighten; reset it as we re-enter hardware range.
    brightness::_apply_boost "$BRIGHTNESS_BOOST_MIN" >/dev/null
  else
    brightness::_apply_boost \
      "$(awk -v b="$(brightness::boost)" -v s="$BRIGHTNESS_BOOST_STEP" 'BEGIN { print b + s }')" >/dev/null
  fi
}

brightness::down() {
  if brightness::boosted; then
    brightness::_apply_boost \
      "$(awk -v b="$(brightness::boost)" -v s="$BRIGHTNESS_BOOST_STEP" 'BEGIN { print b - s }')" >/dev/null
    return 0
  fi
  local current=$(( $(brightness::hardware_percent) ))
  (( current <= BRIGHTNESS_MIN_PERCENT )) && return 0
  if (( current - BRIGHTNESS_STEP_PERCENT < BRIGHTNESS_MIN_PERCENT )); then
    brightness::set_hardware "${BRIGHTNESS_MIN_PERCENT}%"
  else
    brightness::set_hardware "${BRIGHTNESS_STEP_PERCENT}%-"
  fi
}

brightness::reset() { brightness::_apply_boost "$BRIGHTNESS_BOOST_MIN" >/dev/null; }

# brightness::set_percent <0-100> — absolute hardware set, floored so a
# slider can never black the panel out completely.
brightness::set_percent() {
  local pct=$1
  (( pct < 5 )) && pct=5
  (( pct > 100 )) && pct=100
  brightness::set_hardware "${pct}%"
}
