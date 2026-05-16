#!/usr/bin/env bash
set -euo pipefail

dir="$HOME/Pictures/Screenshots"
mkdir -p "$dir"
grimblast selection "$dir/screenshot-$(date +%Y%m%d-%H%M%S).png"
