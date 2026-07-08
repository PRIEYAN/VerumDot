#!/usr/bin/env bash
# Emits JSON describing one calendar month for eww's Calendar Center.
# Usage: calendar-data.sh <year> <month>

year="$1"
month="$2"

python3 - "$year" "$month" <<'PY'
import calendar
import datetime as dt
import json
import sys

year, month = int(sys.argv[1]), int(sys.argv[2])
today = dt.date.today()

weeks = []
for week in calendar.Calendar(firstweekday=0).monthdatescalendar(year, month):
    weeks.append([
        {"day": d.day, "muted": d.month != month, "today": d == today}
        for d in week
    ])

print(json.dumps({
    "title": dt.date(year, month, 1).strftime("%B %Y").upper(),
    "subtitle": today.strftime("%a %d %b %Y").lower(),
    "weeks": weeks,
}))
PY
