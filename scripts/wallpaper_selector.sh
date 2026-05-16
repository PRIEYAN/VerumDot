#!/usr/bin/env bash

# Directory containing wallpapers
WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
# Existing wallpaper script
SET_WALLPAPER_SCRIPT="$HOME/.config/hypr/scripts/wallpaper.sh"

# Check if directory exists
if [[ ! -d "$WALLPAPER_DIR" ]]; then
    notify-send "Wallpaper Selector" "Directory $WALLPAPER_DIR not found."
    exit 1
fi

# Get list of images
files=$(ls "$WALLPAPER_DIR" | grep -E "\.(jpg|jpeg|png|webp|JPG|PNG|WEBP)$")

if [[ -z "$files" ]]; then
    notify-send "Wallpaper Selector" "No images found in $WALLPAPER_DIR"
    exit 1
fi

# Use rofi to select a file
# -dmenu: run in dmenu mode
# -i: case insensitive
# -p: prompt
selected=$(echo "$files" | rofi -dmenu -i -p "Select Wallpaper:")

# If a file was selected, set it
if [[ -n "$selected" ]]; then
    "$SET_WALLPAPER_SCRIPT" set "$WALLPAPER_DIR/$selected"
    notify-send "Wallpaper Selector" "Wallpaper set to $selected"
fi
