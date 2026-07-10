#!/usr/bin/env bash
# Toggle the default microphone (audio source) mute via wpctl, then push the
# fresh state into eww immediately so the icon flips instantly.
wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle

# self-locate so the sibling status script resolves for any user / checkout
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
json=$("$DIR/mic-status.sh")
text=$(printf '%s' "$json" | jq -r '.text // ""')
tooltip=$(printf '%s' "$json" | jq -r '.tooltip // ""')
class=$(printf '%s' "$json" | jq -r '.class // ""')
eww update "mic_text=$text" "mic_tooltip=$tooltip" "mic_class=$class" >/dev/null 2>&1
