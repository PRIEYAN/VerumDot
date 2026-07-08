#!/usr/bin/env python3
"""Battery module for eww. Emits JSON {text, tooltip, class}.

text:    a charge-level glyph + percentage
tooltip: charging/discharging state + estimated time remaining
class:   high|medium|low|charging (drives color, though the bar forces white)

Reads the first battery under /sys/class/power_supply. Time remaining is
computed from energy/charge and power/current when the kernel exposes them.
"""
import glob
import json
import os


def read(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return None


def find_battery():
    for p in sorted(glob.glob("/sys/class/power_supply/BAT*")):
        return p
    # some systems name it differently
    for p in sorted(glob.glob("/sys/class/power_supply/*")):
        if read(os.path.join(p, "type")) == "Battery":
            return p
    return None


GLYPHS_DISCHARGE = ["", "", "", "", "", "", "", "", "", "", ""]
CHARGING_GLYPH = ""


def fmt_time(hours):
    if hours is None or hours <= 0:
        return None
    h = int(hours)
    m = int(round((hours - h) * 60))
    if m == 60:
        h, m = h + 1, 0
    if h > 0:
        return f"{h}h {m:02d}m"
    return f"{m}m"


def main():
    bat = find_battery()
    if not bat:
        print(json.dumps({"text": "", "tooltip": "No battery", "class": "high"}))
        return

    cap = read(os.path.join(bat, "capacity"))
    status = read(os.path.join(bat, "status")) or "Unknown"
    pct = int(cap) if cap and cap.isdigit() else 0

    # energy_* (Wh, µWh) preferred; fall back to charge_* (Ah, µAh)
    now = read(os.path.join(bat, "energy_now")) or read(os.path.join(bat, "charge_now"))
    full = read(os.path.join(bat, "energy_full")) or read(os.path.join(bat, "charge_full"))
    rate = read(os.path.join(bat, "power_now")) or read(os.path.join(bat, "current_now"))

    remaining = None
    try:
        now_i, full_i, rate_i = int(now), int(full), int(rate)
        if rate_i > 0:
            if status == "Charging":
                remaining = (full_i - now_i) / rate_i
            elif status == "Discharging":
                remaining = now_i / rate_i
    except (TypeError, ValueError):
        remaining = None

    if status == "Charging":
        icon = CHARGING_GLYPH
        cls = "charging"
        t = fmt_time(remaining)
        tip = f"Charging — {pct}%" + (f", {t} until full" if t else "")
    else:
        idx = min(len(GLYPHS_DISCHARGE) - 1, pct * (len(GLYPHS_DISCHARGE) - 1) // 100)
        icon = GLYPHS_DISCHARGE[idx]
        cls = "high" if pct >= 60 else "medium" if pct >= 25 else "low"
        t = fmt_time(remaining)
        if status == "Full" or pct >= 99:
            tip = f"Full — {pct}%"
        else:
            tip = f"{pct}%" + (f", {t} remaining" if t else "")

    print(json.dumps({"text": f"{icon} {pct}%", "tooltip": tip, "class": cls}))


if __name__ == "__main__":
    main()
