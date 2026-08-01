#!/usr/bin/env bash

# Screenshot directory

# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../scripts" && pwd)/_paths.sh"
SAVE_DIR="$HOME/Pictures/Screenshots"
mkdir -p "$SAVE_DIR"

if [ "$1" = "take" ]; then
    # Filename with timestamp
    FILE="$SAVE_DIR/screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"

    # Check for dependencies
    if ! command -v grim >/dev/null 2>&1 || ! command -v slurp >/dev/null 2>&1; then
        notify-send "Screenshot Error" "Please install 'grim' and 'slurp' first."
        exit 1
    fi

    # Take screenshot of selected area
    # -g $(slurp): select area
    # "": output file
    if grim -g "$(slurp)" "$FILE"; then
        # Copy to clipboard if wl-copy exists
        if command -v wl-copy >/dev/null 2>&1; then
            wl-copy < "$FILE"
        fi
        
        # Notify success
        notify-send "Screenshot Saved" "Saved to $FILE and copied to clipboard." -i "$FILE"
    else
        notify-send "Screenshot Cancelled" "No area selected."
    fi
    exit 0
fi

# Waybar module output (Icon and Tooltip)
printf '{"text":"","tooltip":"Click to select area and take a screenshot"}\n'
