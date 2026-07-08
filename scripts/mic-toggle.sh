#!/usr/bin/env bash
# Toggle the default microphone (audio source) mute state via wpctl.
wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
