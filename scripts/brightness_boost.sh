#!/usr/bin/env bash

# File paths
STATE_FILE="$HOME/.cache/hypr_brightness_boost"
SHADER_DIR="$HOME/.config/hypr/shaders"
SHADER_FILE="$SHADER_DIR/active_boost.glsl"

# Ensure directories exist
mkdir -p "$SHADER_DIR"
mkdir -p "$(dirname "$STATE_FILE")"

# Read current multiplier (default to 1.0)
if [ -f "$STATE_FILE" ]; then
    CURRENT=$(cat "$STATE_FILE")
else
    CURRENT="1.0"
fi

# Sanity check: Ensure CURRENT is a valid float
if [[ ! "$CURRENT" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    CURRENT="1.0"
fi

ACTION=$1

if [ "$ACTION" = "up" ]; then
    # Increase by 0.1, up to a max of 2.0 (200% brightness)
    NEW=$(awk "BEGIN {print $CURRENT + 0.1}")
    LIMIT_CHECK=$(awk "BEGIN {print ($NEW > 2.0) ? 1 : 0}")
    if [ "$LIMIT_CHECK" -eq 1 ]; then
        NEW="2.0"
    fi
elif [ "$ACTION" = "down" ]; then
    # Decrease by 0.1, down to a min of 1.0 (100% standard hardware maximum)
    NEW=$(awk "BEGIN {print $CURRENT - 0.1}")
    LIMIT_CHECK=$(awk "BEGIN {print ($NEW < 1.0) ? 1 : 0}")
    if [ "$LIMIT_CHECK" -eq 1 ]; then
        NEW="1.0"
    fi
elif [ "$ACTION" = "reset" ]; then
    NEW="1.0"
elif [ "$ACTION" = "get" ]; then
    echo "$CURRENT"
    exit 0
else
    echo "Usage: $0 {up|down|reset|get}"
    exit 1
fi

# Save the new state
echo "$NEW" > "$STATE_FILE"

# Apply shader based on the multiplier
EQUAL_CHECK=$(awk "BEGIN {print ($NEW == 1.0) ? 1 : 0}")
if [ "$EQUAL_CHECK" -eq 1 ]; then
    echo "Disabling brightness boost (Resetting to standard 100% hardware)..."
    hyprctl keyword decoration:screen_shader ""
else
    echo "Setting brightness boost to ${NEW}x..."
    # Generate GLSL shader with the current multiplier
    cat <<EOF > "$SHADER_FILE"
#version 300 es
precision mediump float;

in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;

uniform sampler2D tex;

void main() {
    vec4 pixColor = texture(tex, v_texcoord);
    
    // Software brightness boost: multiply RGB components and clamp to valid range
    pixColor.rgb = clamp(pixColor.rgb * $NEW, 0.0, 1.0);
    
    fragColor = pixColor;
}
EOF
    # Tell Hyprland to load/refresh the screen shader
    hyprctl keyword decoration:screen_shader "$SHADER_FILE"
fi
