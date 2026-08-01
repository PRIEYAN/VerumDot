#!/usr/bin/env python3
import json
from pathlib import Path
bat = Path('/sys/class/power_supply/BAT0')
if bat.exists():
    status = (bat / 'status').read_text().strip()
    capacity = (bat / 'capacity').read_text().strip()
    health = (bat / 'health').read_text().strip() if (bat / 'health').exists() else 'Unknown'
    icon = '' if int(capacity) > 80 else '' if int(capacity) > 40 else '' if int(capacity) > 15 else ''
    # Show a charging bolt next to the battery glyph while plugged in.
    charging = status in ('Charging', 'Full')
    bolt = ' ' if charging else ''
    text = f"{bolt}{icon} {capacity}%"
    tooltip = f"Status: {status} | Health: {health}"
else:
    text = ' AC'
    tooltip = 'No battery present'
print(json.dumps({"text": text, "tooltip": tooltip}))
