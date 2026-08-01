#!/usr/bin/env python3
import json
import subprocess
try:
    volume = subprocess.check_output(['pamixer', '--get-volume']).decode().strip()
    mute = subprocess.check_output(['pamixer', '--get-mute']).decode().strip() in ('true','1')
    icon = '' if not mute else ''
    text = f"{icon} {volume}%"
    tooltip = 'Click to toggle mute | Scroll to change volume'
except Exception:
    text = ' n/a'
    tooltip = 'pamixer not available'
print(json.dumps({'text': text, 'tooltip': tooltip}))
