#!/usr/bin/env bash

STATE_FILE="$HOME/.cache/hypr_brightness_boost"
SHADER_DIR="$HOME/.config/hypr/shaders"
SHADER_FILE="$SHADER_DIR/active_boost.glsl"
TEMP_SHADER_FILE="$SHADER_DIR/active_boost.glsl.tmp"

# Ensure directories exist
mkdir -p "$SHADER_DIR"
mkdir -p "$(dirname "$STATE_FILE")"

# Read current software boost (default to 1.0)
if [ -f "$STATE_FILE" ]; then
    SOFTWARE_BOOST=$(cat "$STATE_FILE")
else
    SOFTWARE_BOOST="1.0"
fi

# Sanity check: Ensure SOFTWARE_BOOST is a valid float
if [[ ! "$SOFTWARE_BOOST" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    SOFTWARE_BOOST="1.0"
fi

# Extremely robust helper to get current hardware brightness percentage
get_hardware_percent() {
    if command -v brightnessctl >/dev/null 2>&1; then
        curr=$(brightnessctl get 2>/dev/null || echo "")
        max=$(brightnessctl max 2>/dev/null || echo "")
        if [ -n "$curr" ] && [ -n "$max" ] && [ "$max" -gt 0 ]; then
            echo $(( curr * 100 / max ))
            return
        fi
    fi
    # Default to 100 if we can't query it
    echo 100
}

ACTION=$1

if [ "$ACTION" = "up" ]; then
    HW_PERCENT=$(get_hardware_percent)
    
    if [ "$HW_PERCENT" -lt 100 ]; then
        # 1. Increase hardware brightness first
        echo "Increasing hardware brightness..."
        brightnessctl set +5% 2>/dev/null || true
        
        # Reset software shader if active
        SOFTWARE_BOOST="1.0"
        echo "1.0" > "$STATE_FILE"
        hyprctl keyword decoration:screen_shader ""
    else
        # 2. Hardware is already at 100%, boost with software shader
        NEW_BOOST=$(awk "BEGIN {print $SOFTWARE_BOOST + 0.05}")
        
        # Upper limit check (max 2.0x boost)
        LIMIT_CHECK=$(awk "BEGIN {print ($NEW_BOOST > 2.0) ? 1 : 0}")
        if [ "$LIMIT_CHECK" -eq 1 ]; then
            NEW_BOOST="2.0"
        fi
        
        echo "$NEW_BOOST" > "$STATE_FILE"
        echo "Hardware at max. Software boost: ${NEW_BOOST}x..."
        
        # Write GLSL shader ATOMICALLY using pure vector-vector operations to bypass compiler pedantry
        cat <<EOF > "$TEMP_SHADER_FILE"
#version 300 es
precision mediump float;
in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;
uniform sampler2D tex;
void main() {
    vec4 pixColor = texture(tex, v_texcoord);
    // Create a vector factor to avoid vector-scalar implicit conversions
    vec3 factor = vec3(float($NEW_BOOST));
    pixColor.rgb = clamp(pixColor.rgb * factor, vec3(0.0), vec3(1.0));
    fragColor = pixColor;
}
EOF
        mv "$TEMP_SHADER_FILE" "$SHADER_FILE"
        hyprctl keyword decoration:screen_shader "$SHADER_FILE"
    fi

elif [ "$ACTION" = "down" ]; then
    # Check if software boost is currently active
    BOOST_ACTIVE=$(awk "BEGIN {print ($SOFTWARE_BOOST > 1.0) ? 1 : 0}")
    
    if [ "$BOOST_ACTIVE" -eq 1 ]; then
        # 1. Decrease software boost first
        NEW_BOOST=$(awk "BEGIN {print $SOFTWARE_BOOST - 0.05}")
        LIMIT_CHECK=$(awk "BEGIN {print ($NEW_BOOST < 1.0) ? 1 : 0}")
        if [ "$LIMIT_CHECK" -eq 1 ]; then
            NEW_BOOST="1.0"
        fi
        
        echo "$NEW_BOOST" > "$STATE_FILE"
        
        EQUAL_CHECK=$(awk "BEGIN {print ($NEW_BOOST == 1.0) ? 1 : 0}")
        if [ "$EQUAL_CHECK" -eq 1 ]; then
            echo "Resetting software boost to normal..."
            hyprctl keyword decoration:screen_shader ""
        else
            echo "Decreasing software brightness boost to ${NEW_BOOST}x..."
            # Update GLSL shader ATOMICALLY using pure vector-vector operations
            cat <<EOF > "$TEMP_SHADER_FILE"
#version 300 es
precision mediump float;
in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;
uniform sampler2D tex;
void main() {
    vec4 pixColor = texture(tex, v_texcoord);
    vec3 factor = vec3(float($NEW_BOOST));
    pixColor.rgb = clamp(pixColor.rgb * factor, vec3(0.0), vec3(1.0));
    fragColor = pixColor;
}
EOF
            mv "$TEMP_SHADER_FILE" "$SHADER_FILE"
            hyprctl keyword decoration:screen_shader "$SHADER_FILE"
        fi
    else
        # 2. Software boost is at 1.0, decrease hardware brightness down to 10% floor
        HW_PERCENT=$(get_hardware_percent)
        if [ "$HW_PERCENT" -gt 10 ]; then
            # Check if decreasing by 5% drops below 10%
            NEW_HW=$(( HW_PERCENT - 5 ))
            if [ "$NEW_HW" -lt 10 ]; then
                echo "Reaching 10% minimum floor..."
                brightnessctl set 10% 2>/dev/null || true
            else
                echo "Decreasing hardware brightness..."
                brightnessctl set 5%- 2>/dev/null || true
            fi
        else
            echo "Already at minimum 10% hardware brightness limit."
        fi
    fi

elif [ "$ACTION" = "reset" ]; then
    echo "1.0" > "$STATE_FILE"
    hyprctl keyword decoration:screen_shader ""
fi
