"""Turn a Hyprland config into the rows the cheat sheet renders.

Four responsibilities, kept apart so each can be exercised on its own:

  KeyFormatter      a chord ("SUPER SHIFT", "w") -> ["Super", "Shift", "W"]
  BindClassifier    a dispatcher and its arguments -> (group, description)
  ConfigReader      a .conf tree -> a flat list of binds
  CheatSheet        binds -> merged, grouped sections

The classifier is the part that needs replacing most often — it is a table
of "what does this command mean to a human" — so it is injected into the
reader rather than reached for as a module global.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass, field
from typing import Iterable

# Sections render in this order; anything unmatched lands in "Other".
GROUP_ORDER = [
    "Apps", "Windows", "Workspaces", "Media & Brightness",
    "Screenshots", "Notifications", "System", "Calendar", "Other",
]


@dataclass(frozen=True)
class Bind:
    group: str
    chord: tuple[str, ...]
    action: str


class KeyFormatter:
    """Renders a modifier set and a key name for display."""

    MODIFIERS = {
        "SUPER": "Super", "SHIFT": "Shift", "CTRL": "Ctrl",
        "CONTROL": "Ctrl", "ALT": "Alt", "MOD1": "Alt",
    }

    KEYS = {
        "return": "Enter", "kp_enter": "Enter", "space": "Space", "tab": "Tab",
        "escape": "Esc", "print": "Print",
        "up": "↑", "down": "↓", "left": "←", "right": "→",
        "mouse_up": "Scroll ↑", "mouse_down": "Scroll ↓",
        "mouse:272": "Left drag", "mouse:273": "Right drag",
        "xf86poweroff": "Power",
        "xf86monbrightnessup": "Brightness ↑", "xf86monbrightnessdown": "Brightness ↓",
        "xf86audioraisevolume": "Vol ↑", "xf86audiolowervolume": "Vol ↓",
        "xf86audiomute": "Mute", "xf86audioplay": "Play",
        "xf86audionext": "Next", "xf86audioprev": "Prev",
        "switch:on:lid switch": "Lid close", "switch:off:lid switch": "Lid open",
    }

    def key(self, name: str) -> str:
        stripped = name.strip()
        named = self.KEYS.get(stripped.lower())
        if named:
            return named
        if len(stripped) == 1:
            return stripped.upper()
        # F1-F12 and anything else keeps its own capitalisation.
        return stripped[:1].upper() + stripped[1:]

    def chord(self, modifiers: str, key: str) -> tuple[str, ...]:
        parts = [
            self.MODIFIERS.get(token.upper(), token.capitalize())
            for token in modifiers.replace("+", " ").split()
        ]
        parts.append(self.key(key))
        return tuple(parts)


class BindClassifier:
    """Maps a bind to the group and wording the cheat sheet shows."""

    # First match wins, so order matters: the more specific pattern leads.
    COMMAND_RULES: list[tuple[str, str, str]] = [
        (r"\bkitty\b|\$term\b", "Apps", "Terminal (kitty)"),
        (r"^code\b", "Apps", "VS Code"),
        (r"^firefox\b", "Apps", "Firefox"),
        (r"^nautilus\b", "Apps", "Files (nautilus)"),
        (r"^spotify\b", "Apps", "Spotify"),
        (r"app-launcher\.sh", "Apps", "App launcher"),
        (r"keybinds.*qs-toggle|qs-toggle\.sh keybinds", "Apps", "This cheat sheet"),
        (r"lockscreen-wallpaper-selector\.sh", "Apps", "Lock-screen wallpaper picker"),
        (r"wallpaper-selector\.sh", "Apps", "Wallpaper picker"),
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
        (r"makoctl dismiss --all", "Notifications", "Dismiss all"),
        (r"makoctl dismiss", "Notifications", "Dismiss newest"),
        (r"makoctl mode .*do-not-disturb", "Notifications", "Toggle Do Not Disturb"),
        (r"brightness-control\.sh up", "Media & Brightness", "Brightness up"),
        (r"brightness-control\.sh down", "Media & Brightness", "Brightness down"),
        # The volume keys now call one script instead of carrying an inline
        # wpctl/pamixer/pactl chain, so these match the verb, not the backend.
        (r"volume-control\.sh up", "Media & Brightness", "Volume up"),
        (r"volume-control\.sh down", "Media & Brightness", "Volume down"),
        (r"volume-control\.sh mute", "Media & Brightness", "Mute toggle"),
        (r"eww-cal\.sh prev", "Calendar", "Previous month"),
        (r"eww-cal\.sh next", "Calendar", "Next month"),
        (r"eww .*close calendar", "Calendar", "Close the calendar"),
    ]

    DISPATCHER_RULES: dict[str, tuple[str, str]] = {
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

    def __init__(self) -> None:
        # Compiled once: this runs over every bind in the config.
        self._commands = [
            (re.compile(pattern, re.IGNORECASE), group, description)
            for pattern, group, description in self.COMMAND_RULES
        ]

    def classify(self, dispatcher: str, args: str) -> tuple[str, str]:
        if dispatcher == "exec":
            return self._classify_command(args.strip())
        if dispatcher == "workspace":
            return self._classify_workspace(args.strip())
        if dispatcher in ("movetoworkspace", "movetoworkspacesilent"):
            quiet = " (stay here)" if dispatcher.endswith("silent") else ""
            return "Workspaces", f"Move window → workspace {args.strip()}{quiet}"
        if dispatcher in self.DISPATCHER_RULES:
            group, template = self.DISPATCHER_RULES[dispatcher]
            return group, template.format(a=args.strip())
        return "Other", f"{dispatcher} {args}".strip()

    def _classify_command(self, command: str) -> tuple[str, str]:
        for pattern, group, description in self._commands:
            if pattern.search(command):
                return group, description
        return "Other", self.humanise(command)

    @staticmethod
    def _classify_workspace(target: str) -> tuple[str, str]:
        if target in ("+1", "e+1"):
            return "Workspaces", "Next workspace"
        if target in ("-1", "e-1"):
            return "Workspaces", "Previous workspace"
        return "Workspaces", f"Workspace {target}"

    @staticmethod
    def humanise(command: str) -> str:
        """A readable fallback for a script the table does not know.

        Keeps an unrecognised bind visible on the cheat sheet instead of
        dropping it — a missing row is much harder to notice than an ugly one.
        """
        parts = command.split()
        name = os.path.basename(parts[0])
        name = re.sub(r"\.(sh|py|bash)$", "", name)
        name = re.sub(r"[-_]+", " ", name).strip()
        label = name[:1].upper() + name[1:]
        arguments = [part for part in parts[1:] if not part.startswith("-")]
        return f"{label} · {' '.join(arguments)}" if arguments else label


class ConfigReader:
    """Parses a Hyprland config tree into Binds."""

    BIND_KEY = re.compile(r"bind[a-z]*")

    def __init__(self, classifier: BindClassifier | None = None,
                 formatter: KeyFormatter | None = None):
        self._classifier = classifier or BindClassifier()
        self._formatter = formatter or KeyFormatter()

    def read(self, path: str) -> list[Bind]:
        binds: list[Bind] = []
        self._read_file(path, {}, binds, set())
        return binds

    def _read_file(self, path: str, variables: dict[str, str],
                   binds: list[Bind], seen: set[str]) -> None:
        real = os.path.realpath(path)
        # `seen` guards against a config that sources itself, directly or
        # through a cycle — which would otherwise recurse until Python gives up.
        if real in seen or not os.path.isfile(real):
            return
        seen.add(real)

        submap = ""
        with open(real, encoding="utf-8", errors="replace") as handle:
            for raw in handle:
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue

                if line.startswith("$"):
                    name, _, value = line[1:].partition("=")
                    variables[name.strip()] = value.strip()
                    continue

                key, separator, value = line.partition("=")
                if not separator:
                    continue
                key, value = key.strip(), value.strip()

                if key == "source":
                    self._read_file(os.path.join(os.path.dirname(real), value),
                                    variables, binds, seen)
                    continue

                if key == "submap":
                    submap = "" if value == "reset" else value
                    continue

                if not self.BIND_KEY.fullmatch(key):
                    continue

                bind = self._parse_bind(value, variables, submap)
                if bind is not None:
                    binds.append(bind)

    def _parse_bind(self, value: str, variables: dict[str, str], submap: str) -> Bind | None:
        # mods, key, dispatcher, args — split only three times, because the
        # argument string may itself contain commas.
        parts = value.split(",", 3)
        if len(parts) < 3:
            return None
        modifiers, key, dispatcher = (part.strip() for part in parts[:3])
        args = self._expand(parts[3].strip() if len(parts) > 3 else "", variables)

        # Switching submaps is bookkeeping, not something to put on a cheat sheet.
        if dispatcher == "submap":
            return None

        group, action = self._classifier.classify(dispatcher, args)
        if submap:
            group = "Calendar" if submap.lower() == "calendar" else submap.capitalize()
        return Bind(group=group, chord=self._formatter.chord(modifiers, key), action=action)

    @staticmethod
    def _expand(value: str, variables: dict[str, str]) -> str:
        """Substitute $vars, longest name first so $menu never eats $menubar."""
        for name in sorted(variables, key=len, reverse=True):
            value = value.replace(f"${name}", variables[name])
        return value


@dataclass
class CheatSheet:
    """Merges and groups binds into the sections the popup renders."""

    binds: Iterable[Bind] = field(default_factory=list)

    def sections(self) -> list[dict]:
        return self._group(self._merge())

    def _merge(self) -> list[dict]:
        """Collapse binds that do the same thing into one row of chords.

        Super+R and Super+Space both open the launcher; the popup shows them
        on a single row rather than repeating the description.
        """
        rows: dict[tuple[str, str], list[list[str]]] = {}
        order: list[tuple[str, str]] = []
        for bind in self.binds:
            slot = (bind.group, bind.action)
            if slot not in rows:
                rows[slot] = []
                order.append(slot)
            chord = list(bind.chord)
            if chord not in rows[slot]:
                rows[slot].append(chord)
        return [{"group": g, "action": a, "keys": rows[(g, a)]} for g, a in order]

    @staticmethod
    def _group(rows: list[dict]) -> list[dict]:
        sections: dict[str, list[dict]] = {}
        for row in rows:
            sections.setdefault(row["group"], []).append(
                {"keys": row["keys"], "action": row["action"]}
            )
        ranked = sorted(
            sections,
            key=lambda group: (GROUP_ORDER.index(group) if group in GROUP_ORDER else 99, group),
        )
        return [{"title": group, "items": sections[group]} for group in ranked]
