#!/usr/bin/env python3
"""Dump this rice's Hyprland keybinds as JSON for the quickshell cheat sheet.

Reads hyprland.conf, follows every `source =`, and turns each bind line into
a row the popup can render:

    {"group": "Apps", "keys": [["Super","T"]], "action": "Terminal (kitty)"}

`keys` is a list of chord variants because several binds share one action
(Super+R and Super+Space both open the launcher); the popup shows them on one
row separated by a dot rather than repeating the description.

    keybinds-dump.py [config]      # default: ../hyprland.conf
"""

import json
import os
import re
import sys

HYPR_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Groups render in this order; anything unmatched lands in "Other".
GROUP_ORDER = [
    "Apps",
    "Windows",
    "Workspaces",
    "Media & Brightness",
    "Screenshots",
    "Notifications",
    "System",
    "Calendar",
    "Other",
]

MOD_NAMES = {
    "SUPER": "Super",
    "SHIFT": "Shift",
    "CTRL": "Ctrl",
    "CONTROL": "Ctrl",
    "ALT": "Alt",
    "MOD1": "Alt",
}

KEY_NAMES = {
    "return": "Enter",
    "kp_enter": "Enter",
    "space": "Space",
    "tab": "Tab",
    "escape": "Esc",
    "print": "Print",
    "up": "↑",
    "down": "↓",
    "left": "←",
    "right": "→",
    "mouse_up": "Scroll ↑",
    "mouse_down": "Scroll ↓",
    "mouse:272": "Left drag",
    "mouse:273": "Right drag",
    "xf86poweroff": "Power",
    "xf86monbrightnessup": "Brightness ↑",
    "xf86monbrightnessdown": "Brightness ↓",
    "xf86audioraisevolume": "Vol ↑",
    "xf86audiolowervolume": "Vol ↓",
    "xf86audiomute": "Mute",
    "xf86audioplay": "Play",
    "xf86audionext": "Next",
    "xf86audioprev": "Prev",
    "switch:on:lid switch": "Lid close",
    "switch:off:lid switch": "Lid open",
}

# command regex -> (group, description). First match wins, so order matters.
COMMAND_RULES = [
    (r"\bkitty\b|\$term\b", "Apps", "Terminal (kitty)"),
    (r"^code\b", "Apps", "VS Code"),
    (r"^firefox\b", "Apps", "Firefox"),
    (r"^nautilus\b", "Apps", "Files (nautilus)"),
    (r"^spotify\b", "Apps", "Spotify"),
    (r"app-launcher\.sh", "Apps", "App launcher"),
    (r"keybinds.*qs-toggle|qs-toggle\.sh keybinds", "Apps", "This cheat sheet"),
    (r"lockscreen_wallpaper_selector\.sh", "Apps", "Lock-screen wallpaper picker"),
    (r"wallpaper_selector\.sh", "Apps", "Wallpaper picker"),
    (r"hyprlock", "System", "Lock screen"),
    (r"power-menu\.sh", "System", "Power menu"),
    (r"performance-mode\.sh", "System", "Cycle CPU power mode"),
    (r"hidden-workspace-open\.sh", "Workspaces", "Open hidden workspace"),
    (r"hidden-workspace-close\.sh", "Workspaces", "Close hidden workspace"),
    (r"hyprctl reload", "System", "Reload Hyprland config"),
    (r"lid-close\.sh", "System", "Lock and blank on lid close"),
    (r"display-restore\.sh", "System", "Wake the panel on lid open"),
    (r"screenshot\.sh full", "Screenshots", "Whole screen"),
    (r"screenshot\.sh selection", "Screenshots", "Select a region"),
    (r"screenRecord\.sh", "Screenshots", "Screen recording"),
    (r"makoctl dismiss --all", "Notifications", "Dismiss all"),
    (r"makoctl dismiss", "Notifications", "Dismiss newest"),
    (r"makoctl mode .*do-not-disturb", "Notifications", "Toggle Do Not Disturb"),
    (r"brightness_control\.sh up", "Media & Brightness", "Brightness up"),
    (r"brightness_control\.sh down", "Media & Brightness", "Brightness down"),
    (r"set-volume.*%\+|-i 5|\+5%", "Media & Brightness", "Volume up"),
    (r"set-volume.*%-|-d 5|-5%", "Media & Brightness", "Volume down"),
    (r"set-mute|pamixer -t", "Media & Brightness", "Mute toggle"),
    (r"eww-cal\.sh prev", "Calendar", "Previous month"),
    (r"eww-cal\.sh next", "Calendar", "Next month"),
    (r"eww .*close calendar", "Calendar", "Close the calendar"),
]

# dispatcher -> (group, description template). `{a}` is the argument string.
DISPATCHER_RULES = {
    "killactive": ("Windows", "Close active window"),
    "fullscreen": ("Windows", "Toggle fullscreen"),
    "togglefloating": ("Windows", "Toggle floating"),
    "movewindow": ("Windows", "Move window"),
    "resizewindow": ("Windows", "Resize window"),
    "pin": ("Windows", "Pin window"),
    "focuswindow": ("Windows", "Focus {a} window"),
    "movefocus": ("Windows", "Focus {a}"),
    "exit": ("System", "Exit Hyprland"),
}


def humanise_script(cmd):
    """Fallback description for a script this table does not know."""
    parts = cmd.split()
    name = os.path.basename(parts[0])
    name = re.sub(r"\.(sh|py|bash)$", "", name)
    name = re.sub(r"[-_]+", " ", name).strip()
    label = name[:1].upper() + name[1:]
    args = [a for a in parts[1:] if not a.startswith("-")]
    return f"{label} · {' '.join(args)}" if args else label


def classify(dispatcher, args):
    """Return (group, description) for one bind's dispatcher + arguments."""
    if dispatcher == "exec":
        cmd = args.strip()
        for pattern, group, desc in COMMAND_RULES:
            if re.search(pattern, cmd, re.IGNORECASE):
                return group, desc
        return "Other", humanise_script(cmd)

    if dispatcher == "workspace":
        a = args.strip()
        if a in ("+1", "e+1"):
            return "Workspaces", "Next workspace"
        if a in ("-1", "e-1"):
            return "Workspaces", "Previous workspace"
        return "Workspaces", f"Workspace {a}"

    if dispatcher in ("movetoworkspace", "movetoworkspacesilent"):
        quiet = " (stay here)" if dispatcher.endswith("silent") else ""
        return "Workspaces", f"Move window → workspace {args.strip()}{quiet}"

    if dispatcher in DISPATCHER_RULES:
        group, template = DISPATCHER_RULES[dispatcher]
        return group, template.format(a=args.strip())

    return "Other", f"{dispatcher} {args}".strip()


def pretty_key(key):
    k = key.strip()
    named = KEY_NAMES.get(k.lower())
    if named:
        return named
    if len(k) == 1:
        return k.upper()
    # F1-F12 and anything else keeps its own capitalisation.
    return k[:1].upper() + k[1:]


def pretty_chord(mods, key):
    out = []
    for m in mods.replace("+", " ").split():
        out.append(MOD_NAMES.get(m.upper(), m.capitalize()))
    out.append(pretty_key(key))
    return out


def expand(value, variables):
    """Substitute $vars, longest name first so $menu never eats $menubar."""
    for name in sorted(variables, key=len, reverse=True):
        value = value.replace(f"${name}", variables[name])
    return value


def read_config(path, variables, binds, seen):
    """Parse one conf file, recursing through its `source =` lines."""
    real = os.path.realpath(path)
    if real in seen or not os.path.isfile(real):
        return
    seen.add(real)

    submap = ""
    for raw in open(real, encoding="utf-8", errors="replace"):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue

        if line.startswith("$"):
            name, _, value = line[1:].partition("=")
            variables[name.strip()] = value.strip()
            continue

        key, sep, value = line.partition("=")
        if not sep:
            continue
        key, value = key.strip(), value.strip()

        if key == "source":
            read_config(os.path.join(os.path.dirname(real), value), variables, binds, seen)
            continue

        if key == "submap":
            submap = "" if value == "reset" else value
            continue

        # bind, bindm, bindl, bindel, binde… all share the same argument shape.
        if not re.fullmatch(r"bind[a-z]*", key):
            continue

        # mods, key, dispatcher, args… — the args may themselves contain commas.
        parts = value.split(",", 3)
        if len(parts) < 3:
            continue
        mods, keyname, dispatcher = (p.strip() for p in parts[:3])
        args = expand(parts[3].strip() if len(parts) > 3 else "", variables)

        # submap switching is bookkeeping, not something to put on a cheat sheet.
        if dispatcher == "submap":
            continue

        group, desc = classify(dispatcher, args)
        if submap:
            group = submap.capitalize() if submap.lower() != "calendar" else "Calendar"
        binds.append({"group": group, "chord": pretty_chord(mods, keyname), "action": desc})


def merge(binds):
    """Collapse binds that do the same thing into one row with several chords."""
    rows = {}
    order = []
    for b in binds:
        slot = (b["group"], b["action"])
        if slot not in rows:
            rows[slot] = []
            order.append(slot)
        if b["chord"] not in rows[slot]:
            rows[slot].append(b["chord"])
    return [{"group": g, "action": a, "keys": rows[(g, a)]} for g, a in order]


def group_sections(rows):
    sections = {}
    for row in rows:
        sections.setdefault(row["group"], []).append(
            {"keys": row["keys"], "action": row["action"]}
        )
    ranked = sorted(sections, key=lambda g: (GROUP_ORDER.index(g) if g in GROUP_ORDER else 99, g))
    return [{"title": g, "items": sections[g]} for g in ranked]


def main():
    config = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HYPR_DIR, "hyprland.conf")
    binds = []
    read_config(config, {}, binds, set())
    json.dump(group_sections(merge(binds)), sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
