#!/usr/bin/env python3

import pathlib
import subprocess
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, Gtk, Pango


WALLPAPER_DIR = pathlib.Path.home() / "Pictures" / "Wallpapers"
SET_WALLPAPER = pathlib.Path.home() / ".config" / "hypr" / "scripts" / "wallpaper.sh"
EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}

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

.search {
  margin: 10px 16px 0;
  padding: 6px 10px;
  border-radius: 4px;
  background: transparent;
  border: 1px solid rgba(255, 255, 255, 0.10);
  color: #ffffff;
  font-size: 11px;
  box-shadow: none;
  caret-color: #ffffff;
}

.search:focus {
  border-color: rgba(255, 255, 255, 0.30);
}

.viewport {
  padding: 10px 12px 12px;
}

.tile {
  background: transparent;
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 4px;
  padding: 0;
  box-shadow: none;
}

.tile:hover {
  border-color: rgba(255, 255, 255, 0.45);
  background: transparent;
}

.thumb {
  border-radius: 0;
}

.name {
  color: rgba(255, 255, 255, 0.65);
  font-size: 9px;
  font-weight: 500;
  padding: 4px 6px;
  letter-spacing: 0.3px;
}

.empty {
  color: rgba(255, 255, 255, 0.40);
  padding: 30px;
  font-size: 11px;
}
"""


class WallpaperCenter(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="local.hypr.WallpaperCenter")
        self.window = None
        self.flow = None
        self.subtitle = None
        self.search = None
        self.files = []

    def do_activate(self):
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS.encode())
        display = Gdk.Display.get_default()
        if display is None:
            print("Wallpaper selector needs a graphical display.", file=sys.stderr)
            self.quit()
            return
        Gtk.StyleContext.add_provider_for_display(display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        self.window = Gtk.ApplicationWindow(application=self)
        self.window.set_title("Wallpaper Center")
        self.window.set_default_size(560, 480)
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
        title = Gtk.Label(label="WALLPAPERS", xalign=0)
        title.add_css_class("title")
        self.subtitle = Gtk.Label(xalign=0)
        self.subtitle.add_css_class("subtitle")
        heading.append(title)
        heading.append(self.subtitle)
        topbar.append(heading)

        close = Gtk.Button(label="x")
        close.add_css_class("close")
        close.connect("clicked", lambda *_: self.window.close())
        topbar.append(close)

        self.search = Gtk.SearchEntry()
        self.search.add_css_class("search")
        self.search.set_placeholder_text("filter")
        self.search.connect("search-changed", lambda *_: self.render())
        root.append(self.search)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.add_css_class("viewport")
        scroll.set_vexpand(True)
        self.flow = Gtk.FlowBox()
        self.flow.set_max_children_per_line(3)
        self.flow.set_min_children_per_line(3)
        self.flow.set_selection_mode(Gtk.SelectionMode.NONE)
        self.flow.set_row_spacing(8)
        self.flow.set_column_spacing(8)
        self.flow.set_homogeneous(True)
        scroll.set_child(self.flow)
        root.append(scroll)

        key = Gtk.EventControllerKey()
        key.connect("key-pressed", self.handle_key)
        self.window.add_controller(key)

        self.files = self.load_files()
        self.render()
        self.window.present()

    def handle_key(self, _controller, keyval, _keycode, _state):
        if keyval == Gdk.KEY_Escape:
            self.window.close()
            return True
        return False

    def load_files(self):
        if not WALLPAPER_DIR.exists():
            return []
        return sorted(
            [path for path in WALLPAPER_DIR.iterdir() if path.suffix.lower() in EXTENSIONS],
            key=lambda path: path.name.lower(),
        )

    def render(self):
        child = self.flow.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            self.flow.remove(child)
            child = nxt

        query = self.search.get_text().lower() if self.search else ""
        files = [path for path in self.files if query in path.name.lower()]
        self.subtitle.set_text(f"{len(files)} files")
        if not files:
            empty = Gtk.Label(label="no wallpapers found")
            empty.add_css_class("empty")
            self.flow.append(empty)
            return

        for path in files:
            self.flow.append(self.tile(path))

    def tile(self, path):
        button = Gtk.Button()
        button.add_css_class("tile")
        button.connect("clicked", lambda *_: self.set_wallpaper(path))

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        picture = Gtk.Picture.new_for_filename(str(path))
        picture.add_css_class("thumb")
        picture.set_content_fit(Gtk.ContentFit.COVER)
        picture.set_size_request(160, 90)
        label = Gtk.Label(label=path.stem.lower(), xalign=0)
        label.add_css_class("name")
        label.set_ellipsize(Pango.EllipsizeMode.END)
        box.append(picture)
        box.append(label)
        button.set_child(box)
        return button

    def set_wallpaper(self, path):
        subprocess.Popen([str(SET_WALLPAPER), "set", str(path)])
        if Gtk.Application.get_default():
            self.window.close()


WallpaperCenter().run([sys.argv[0]])
