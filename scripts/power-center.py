#!/usr/bin/env python3

import subprocess
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, Gtk


CSS = """
window { background: transparent; }

.root {
  background: rgba(0, 0, 0, 0.82);
  border: 1px solid rgba(255, 255, 255, 0.10);
  border-radius: 10px;
  color: #ffffff;
  font-family: "Iosevka Term", monospace;
}

.topbar {
  padding: 14px 16px 10px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.08);
}

.title {
  font-size: 14px;
  font-weight: 700;
  color: #ffffff;
  letter-spacing: 0.5px;
}

.subtitle {
  color: rgba(255, 255, 255, 0.40);
  font-size: 10px;
}

.close {
  min-width: 24px;
  min-height: 24px;
  padding: 0 6px;
  border-radius: 4px;
  background: transparent;
  border: none;
  color: rgba(255, 255, 255, 0.55);
  font-weight: 600;
  font-size: 12px;
  box-shadow: none;
}

.close:hover {
  background: rgba(255, 255, 255, 0.06);
  color: #ffffff;
}

.grid {
  padding: 14px;
}

.action {
  background: transparent;
  border: 1px solid rgba(255, 255, 255, 0.10);
  border-radius: 6px;
  color: #ffffff;
  font-size: 11px;
  font-weight: 500;
  letter-spacing: 0.5px;
  padding: 18px 10px;
  min-height: 70px;
  min-width: 110px;
  box-shadow: none;
}

.action:hover {
  background: rgba(255, 255, 255, 0.06);
  border-color: rgba(255, 255, 255, 0.45);
}

.action.danger:hover {
  background: #ffffff;
  color: #000000;
  border-color: #ffffff;
}

.glyph {
  font-size: 22px;
  font-weight: 400;
  color: inherit;
}

.label {
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 1px;
  color: inherit;
}
"""


HYPR_CONFIG = "/home/prieyan/.config/hypr/apps/hyprlock/hyprlock.conf"
SHUTDOWN_SCRIPT = "/home/prieyan/.config/hypr/scripts/mogger_shutdown.sh"


ACTIONS = [
    ("lock",     "LOCK",     ["hyprlock", "-c", HYPR_CONFIG],     False),
    ("⏾",       "SUSPEND",  ["systemctl", "suspend"],            False),
    ("→",       "LOGOUT",   ["hyprctl", "dispatch", "exit"],     False),
    ("↻",       "REBOOT",   ["systemctl", "reboot"],             True),
    ("⏻",       "SHUTDOWN", [SHUTDOWN_SCRIPT],                   True),
]


class PowerCenter(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="local.hypr.PowerCenter")
        self.window = None

    def do_activate(self):
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS.encode())
        display = Gdk.Display.get_default()
        if display is None:
            print("Power Center needs a graphical display.", file=sys.stderr)
            self.quit()
            return
        Gtk.StyleContext.add_provider_for_display(
            display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        self.window = Gtk.ApplicationWindow(application=self)
        self.window.set_title("Power Center")
        self.window.set_default_size(380, 280)
        self.window.set_resizable(False)
        self.window.set_decorated(False)

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        root.add_css_class("root")
        self.window.set_child(root)

        topbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        topbar.add_css_class("topbar")
        root.append(topbar)

        heading = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        heading.set_hexpand(True)
        title = Gtk.Label(label="POWER", xalign=0)
        title.add_css_class("title")
        subtitle = Gtk.Label(label="session controls", xalign=0)
        subtitle.add_css_class("subtitle")
        heading.append(title)
        heading.append(subtitle)
        topbar.append(heading)

        close = Gtk.Button(label="x")
        close.add_css_class("close")
        close.connect("clicked", lambda *_: self.window.close())
        topbar.append(close)

        grid = Gtk.Grid(column_spacing=8, row_spacing=8)
        grid.add_css_class("grid")
        grid.set_column_homogeneous(True)
        grid.set_row_homogeneous(True)
        root.append(grid)

        for index, (glyph, label, cmd, danger) in enumerate(ACTIONS):
            button = self.action_button(glyph, label, cmd, danger)
            col = index % 3
            row = index // 3
            grid.attach(button, col, row, 1, 1)

        key = Gtk.EventControllerKey()
        key.connect("key-pressed", self.handle_key)
        self.window.add_controller(key)

        self.window.present()

    def action_button(self, glyph, label, cmd, danger):
        button = Gtk.Button()
        button.add_css_class("action")
        if danger:
            button.add_css_class("danger")

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        box.set_halign(Gtk.Align.CENTER)
        box.set_valign(Gtk.Align.CENTER)

        glyph_label = Gtk.Label(label=glyph)
        glyph_label.add_css_class("glyph")
        text_label = Gtk.Label(label=label)
        text_label.add_css_class("label")
        box.append(glyph_label)
        box.append(text_label)

        button.set_child(box)
        button.connect("clicked", lambda *_: self.run_action(cmd))
        return button

    def run_action(self, cmd):
        self.window.close()
        subprocess.Popen(cmd)

    def handle_key(self, _controller, keyval, _keycode, _state):
        if keyval == Gdk.KEY_Escape:
            self.window.close()
            return True
        return False


PowerCenter().run([sys.argv[0]])
