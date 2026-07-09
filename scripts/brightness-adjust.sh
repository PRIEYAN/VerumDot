#!/usr/bin/env bash
# Unified brightness on a single 10..150 scale, crossing two mechanisms at 100:
#   10..100  -> hardware backlight via brightnessctl (boost shader off)
#   100..150 -> backlight pinned 100%, GLSL boost shader 1.0x..1.5x
# Adjusts by 5 per scroll and pushes the level into eww in one update.
# Usage: brightness-adjust.sh up|down

MIN=10
MAX=150
STEP=5
BOOST="/home/prieyan/.config/hypr/scripts/brightness_boost.sh"

# --- read current unified level -------------------------------------------
# hardware percent (0..100)
hw=$(brightnessctl -m 2>/dev/null | awk -F, '{gsub("%","",$4); print $4}')
hw=${hw:-100}
# boost multiplier (1.0..2.0); level contribution above 100 is (mult-1)*100
mult=$(bash "$BOOST" get 2>/dev/null); mult=${mult:-1.0}

# If boost is engaged (>1.0), the level is 100 + (mult-1)*100; else it's hw.
boost_active=$(awk "BEGIN{print ($mult > 1.0) ? 1 : 0}")
if [ "$boost_active" -eq 1 ]; then
  level=$(awk "BEGIN{printf \"%d\", 100 + ($mult - 1.0) * 100 + 0.5}")
else
  level=$hw
fi

# --- adjust ----------------------------------------------------------------
case "$1" in
  up)   level=$(( level + STEP )) ;;
  down) level=$(( level - STEP )) ;;
esac
[ "$level" -gt "$MAX" ] && level=$MAX
[ "$level" -lt "$MIN" ] && level=$MIN

# --- apply to the right mechanism -----------------------------------------
if [ "$level" -le 100 ]; then
  # hardware range: ensure any boost shader is off, set backlight
  [ "$boost_active" -eq 1 ] && bash "$BOOST" reset >/dev/null 2>&1
  brightnessctl set "${level}%" -q
else
  # boost range: pin backlight at 100, drive shader multiplier to level/100
  brightnessctl set 100% -q
  target_mult=$(awk "BEGIN{printf \"%.2f\", $level / 100.0}")
  # brightness_boost.sh steps by 0.1 up/reset only; write the multiplier and
  # apply the shader directly so we can jump straight to target_mult.
  state="$HOME/.cache/hypr_brightness_boost"
  shader="$HOME/.config/hypr/shaders/active_boost.glsl"
  mkdir -p "$(dirname "$shader")" "$(dirname "$state")"
  printf '%s\n' "$target_mult" > "$state"
  cat > "$shader" <<EOF
#version 300 es
precision mediump float;
in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;
uniform sampler2D tex;
void main() {
    vec4 pixColor = texture(tex, v_texcoord);
    pixColor.rgb = clamp(pixColor.rgb * ${target_mult}, 0.0, 1.0);
    fragColor = pixColor;
}
EOF
  hyprctl keyword decoration:screen_shader "$shader" >/dev/null 2>&1
fi

# --- glyph + eww update ----------------------------------------------------
if   [ "$level" -gt 100 ]; then icon=$(printf '\xf3\xb0\x83\xa0')   # brightness-7 (boost)
elif [ "$level" -ge 66 ];  then icon=$(printf '\xf3\xb0\x83\xa0')   # brightness-7
elif [ "$level" -ge 33 ];  then icon=$(printf '\xf3\xb0\x83\x9e')   # brightness-5
else                            icon=$(printf '\xf3\xb0\x83\x9d')   # brightness-4
fi

eww update "brightness_text=${icon} ${level}%" \
           "brightness_tooltip=Brightness: ${level}%$([ "$level" -gt 100 ] && echo ' (boost)')  (scroll to adjust)" \
  >/dev/null 2>&1
