#!/usr/bin/env bash

CACHE_FILE="$HOME/.cache/hypr_wallpaper"
DEFAULT_WALLPAPER="/usr/share/hypr/wall0.png"
WATCHER_PID_FILE="$HOME/.cache/hypr_wallpaper_watcher.pid"

# Ensure cache dir exists
mkdir -p "$(dirname "$CACHE_FILE")"

set_wallpaper() {
    local img="$1"
    
    # Check if file exists, else use default
    if [[ ! -f "$img" ]]; then
        img="$DEFAULT_WALLPAPER"
    fi

    # Persist choice
    echo "$img" > "$CACHE_FILE"
    
    # Preload the image
    hyprctl hyprpaper preload "$img" >/dev/null 2>&1
    
    # Set it on all monitors
    local monitors=$(hyprctl monitors | grep "Monitor" | awk '{print $2}')
    for m in $monitors; do
        hyprctl hyprpaper wallpaper "$m,$img" >/dev/null 2>&1
    done
    
    # Unload all other preloads to keep memory clean
    hyprctl hyprpaper unload all >/dev/null 2>&1
    hyprctl hyprpaper preload "$img" >/dev/null 2>&1

    # Start watcher for this file
    start_watcher "$img"
}

start_watcher() {
    local img="$1"
    
    # Kill previous watcher
    if [[ -f "$WATCHER_PID_FILE" ]]; then
        local pid=$(cat "$WATCHER_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
        fi
        rm "$WATCHER_PID_FILE"
    fi

    # Don't watch the default wallpaper
    if [[ "$img" == "$DEFAULT_WALLPAPER" ]]; then
        return
    fi

    # Background watcher
    (
        # Wait for deletion
        inotifywait -e delete_self "$img" >/dev/null 2>&1
        # Fallback to default
        "$0" set "$DEFAULT_WALLPAPER"
    ) &
    echo $! > "$WATCHER_PID_FILE"
}

init() {
    # Ensure hyprpaper is running
    if ! pgrep -x "hyprpaper" > /dev/null; then
        hyprpaper &
        sleep 0.5
    fi

    if [[ -f "$CACHE_FILE" ]]; then
        set_wallpaper "$(cat "$CACHE_FILE")"
    else
        set_wallpaper "$DEFAULT_WALLPAPER"
    fi
}

case "$1" in
    set)
        set_wallpaper "$2"
        ;;
    init)
        init
        ;;
    *)
        echo "Usage: $0 {set path/to/img|init}"
        exit 1
        ;;
esac
