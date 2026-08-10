#!/usr/bin/env python3
# Gathers CPU / RAM / GPU / SWAP / TEMP for the profile dropdown.
# Printed as plain "key value alert" lines so the caller (bash) can
# stay ignorant of how each number was computed.
import re
import subprocess


def run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, check=True, timeout=2).stdout.strip()
    except Exception:
        return ""


def cpu_percent():
    with open("/proc/stat") as f:
        a = [int(x) for x in f.readline().split()[1:]]
    import time
    time.sleep(0.1)
    with open("/proc/stat") as f:
        b = [int(x) for x in f.readline().split()[1:]]
    idle_a, idle_b = a[3] + a[4], b[3] + b[4]
    total_a, total_b = sum(a), sum(b)
    dt, di = total_b - total_a, idle_b - idle_a
    return round(100 * (dt - di) / dt) if dt else 0


def mem():
    vals = {}
    with open("/proc/meminfo") as f:
        for line in f:
            k, v = line.split(":")
            vals[k] = int(v.strip().split()[0])  # kB
    total = vals.get("MemTotal", 0)
    avail = vals.get("MemAvailable", 0)
    used = total - avail
    swap_total = vals.get("SwapTotal", 0)
    swap_free = vals.get("SwapFree", 0)
    swap_used = swap_total - swap_free
    return used, total, swap_used, swap_total


def gpu_percent():
    out = run(["nvidia-smi", "--query-gpu=utilization.gpu", "--format=csv,noheader,nounits"])
    if out:
        try:
            return round(float(out.splitlines()[0]))
        except ValueError:
            pass
    return None


def temp_c():
    out = run(["sensors", "-A"])
    best = None
    for line in out.splitlines():
        m = re.search(r"\+([\d.]+)\s*°C", line)
        if m:
            val = float(m.group(1))
            if best is None or val > best:
                best = val
    return round(best) if best is not None else None


def gib(kb):
    return kb / (1024 * 1024)


cpu = cpu_percent()
used_kb, total_kb, swap_used_kb, swap_total_kb = mem()
ram_pct = round(100 * used_kb / total_kb) if total_kb else 0
swap_pct = round(100 * swap_used_kb / swap_total_kb) if swap_total_kb else 0
gpu = gpu_percent()
temp = temp_c()

print(f"CPU {cpu} {cpu}% cpu")
print(f"RAM {ram_pct} {gib(used_kb):.1f}G/{gib(total_kb):.1f}G ram")
if gpu is not None:
    print(f"GPU {gpu} {gpu}% gpu")
if swap_total_kb:
    print(f"SWAP {swap_pct} {gib(swap_used_kb):.1f}G/{gib(swap_total_kb):.1f}G swap")
if temp is not None:
    print(f"TEMP {temp} {temp}°C temp")
