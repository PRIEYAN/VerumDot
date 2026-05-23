#!/usr/bin/env bash

# Create a temporary rofi theme for the splash screen
cat << 'EOF' > /tmp/mogger.rasi
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
rofi -e "MOGGER" -theme /tmp/mogger.rasi &
ROFI_PID=$!

# Wait 1 second
sleep 1

# Kill the splash screen
kill $ROFI_PID

# Shutdown the system
systemctl poweroff
