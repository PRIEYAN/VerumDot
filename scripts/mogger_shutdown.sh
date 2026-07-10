#!/usr/bin/env bash

# per-user runtime scratch theme (one var keeps write + -theme in sync)
theme="${XDG_RUNTIME_DIR:-/tmp}/mogger.rasi"

# Create a temporary rofi theme for the splash screen
cat << 'EOF' > "$theme"
* {
    background-color: black;
    text-color: red;
}
window {
    fullscreen: true;
    padding: 40% 0%;
}
textbox {
    font: "Impact 150";
    horizontal-align: 0.5;
    vertical-align: 0.5;
}
EOF

# Show the splash screen
rofi -e "MOGGER" -theme "$theme" &
ROFI_PID=$!

# Wait 1 second
sleep 1

# Kill the splash screen
kill $ROFI_PID

# Shutdown the system
systemctl poweroff
