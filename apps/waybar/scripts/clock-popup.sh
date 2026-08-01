#!/usr/bin/env bash

# Resolve rice root (portable)
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../scripts" && pwd)/_paths.sh"
cal_output=$(cal -3)
date_output=$(date "+%A, %B %d %Y  %H:%M:%S")
rofi -dmenu -p "Calendar" -mesg "$date_output

$cal_output" -theme-str 'window { width: 30em; }' <<<" "
