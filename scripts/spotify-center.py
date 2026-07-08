#!/usr/bin/env python3

import hashlib
import os
import subprocess
import sys
import threading
import urllib.request

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk


PLAYER = "spotify"
ART_DIR = "/tmp/spotify-center-art"


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
  padding: 14px 16px 8px;
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

.close-button {
  min-width: 24px;
  min-height: 24px;
  padding: 0 6px;
  background: transparent;
  border-radius: 4px;
  color: rgba(255, 255, 255, 0.55);
  border: none;
  font-size: 12px;
  font-weight: 600;
  box-shadow: none;
}

.close-button:hover {
  background: rgba(255, 255, 255, 0.06);
  color: #ffffff;
}

.content {
  padding: 16px;
}

.art {
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid rgba(255, 255, 255, 0.08);
}

.track-title {
  font-size: 14px;
  font-weight: 700;
  color: #ffffff;
  margin-top: 14px;
}

.track-artist {
  font-size: 11px;
  font-weight: 500;
  color: rgba(255, 255, 255, 0.65);
  margin-top: 2px;
}

.track-album {
  font-size: 10px;
  color: rgba(255, 255, 255, 0.35);
  margin-top: 1px;
}

scale {
  margin-top: 14px;
  padding: 0;
}

scale trough {
  background: rgba(255, 255, 255, 0.12);
  border-radius: 3px;
  min-height: 4px;
}

scale highlight {
  background: #1db954;
  border-radius: 3px;
  min-height: 4px;
}

scale slider {
  background: #ffffff;
  border-radius: 50%;
  min-width: 12px;
  min-height: 12px;
  margin: -5px;
}

.time-row {
  margin-top: 2px;
}

.time {
  color: rgba(255, 255, 255, 0.45);
  font-size: 9px;
  letter-spacing: 0.3px;
}

.controls {
  margin-top: 14px;
}

.ctl {
  min-width: 40px;
  min-height: 40px;
  border-radius: 50%;
  background: transparent;
  border: 1px solid rgba(255, 255, 255, 0.14);
  color: #ffffff;
  font-size: 14px;
  box-shadow: none;
}

.ctl:hover {
  background: rgba(255, 255, 255, 0.06);
  border-color: rgba(255, 255, 255, 0.30);
}

.ctl.play {
  background: #ffffff;
  color: #000000;
  border-color: #ffffff;
  min-width: 48px;
  min-height: 48px;
  font-size: 16px;
}

.ctl.play:hover {
  background: rgba(255, 255, 255, 0.85);
}

.empty {
  color: rgba(255, 255, 255, 0.40);
  padding: 40px 16px;
  font-size: 11px;
}
"""


def out(args):
    try:
        return subprocess.run(args, text=True, capture_output=True).stdout.strip()
    except Exception:
        return ""


def player_cmd(*args):
    subprocess.run(["playerctl", "-p", PLAYER, *args], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def fmt_time(micros):
    seconds = max(0, int(micros // 1_000_000))
    return f"{seconds // 60}:{seconds % 60:02d}"


class SpotifyCenter(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="local.hypr.SpotifyCenter")
        self.window = None
        self.art = None
        self.track_title = None
        self.track_artist = None
        self.track_album = None
        self.scale = None
        self.pos_label = None
        self.len_label = None
        self.play_button = None
        self.body = None
        self.empty_label = None
        self.length = 0
        self.user_seeking = False
        self.current_art_url = None

    def do_activate(self):
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS.encode())
        display = Gdk.Display.get_default()
        if display is None:
            print("Spotify Center needs a graphical display.", file=sys.stderr)
            self.quit()
            return
        Gtk.StyleContext.add_provider_for_display(display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        os.makedirs(ART_DIR, exist_ok=True)

        self.window = Gtk.ApplicationWindow(application=self)
        self.window.set_title("Spotify Center")
        self.window.set_default_size(340, 470)
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
        title = Gtk.Label(label="SPOTIFY", xalign=0)
        title.add_css_class("title")
        subtitle = Gtk.Label(label="now playing", xalign=0)
        subtitle.add_css_class("subtitle")
        heading.append(title)
        heading.append(subtitle)
        topbar.append(heading)

        close = Gtk.Button(label="x")
        close.add_css_class("close-button")
        close.connect("clicked", lambda *_: self.window.close())
        topbar.append(close)

        self.body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.body.add_css_class("content")
        root.append(self.body)

        # Album art
        self.art = Gtk.Image()
        self.art.add_css_class("art")
        self.art.set_pixel_size(280)
        self.body.append(self.art)

        # Track info
        self.track_title = Gtk.Label(xalign=0)
        self.track_title.add_css_class("track-title")
        self.track_title.set_wrap(True)
        self.track_title.set_max_width_chars(34)
        self.track_artist = Gtk.Label(xalign=0)
        self.track_artist.add_css_class("track-artist")
        self.track_album = Gtk.Label(xalign=0)
        self.track_album.add_css_class("track-album")
        self.body.append(self.track_title)
        self.body.append(self.track_artist)
        self.body.append(self.track_album)

        # Timeline
        self.scale = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL)
        self.scale.set_range(0, 1)
        self.scale.set_draw_value(False)
        self.scale.set_hexpand(True)
        self.scale.connect("change-value", self.on_seek)
        self.body.append(self.scale)

        time_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        time_row.add_css_class("time-row")
        self.pos_label = Gtk.Label(label="0:00", xalign=0)
        self.pos_label.add_css_class("time")
        self.pos_label.set_hexpand(True)
        self.len_label = Gtk.Label(label="0:00", xalign=1)
        self.len_label.add_css_class("time")
        time_row.append(self.pos_label)
        time_row.append(self.len_label)
        self.body.append(time_row)

        # Controls
        controls = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
        controls.add_css_class("controls")
        controls.set_halign(Gtk.Align.CENTER)
        prev_button = Gtk.Button(label="󰒮")
        prev_button.add_css_class("ctl")
        prev_button.connect("clicked", lambda *_: self.control("previous"))
        self.play_button = Gtk.Button(label="")
        self.play_button.add_css_class("ctl")
        self.play_button.add_css_class("play")
        self.play_button.connect("clicked", lambda *_: self.control("play-pause"))
        next_button = Gtk.Button(label="󰒭")
        next_button.add_css_class("ctl")
        next_button.connect("clicked", lambda *_: self.control("next"))
        controls.append(prev_button)
        controls.append(self.play_button)
        controls.append(next_button)
        self.body.append(controls)

        self.empty_label = Gtk.Label(label="nothing playing on spotify")
        self.empty_label.add_css_class("empty")
        self.empty_label.set_visible(False)
        root.append(self.empty_label)

        key = Gtk.EventControllerKey()
        key.connect("key-pressed", self.handle_key)
        self.window.add_controller(key)

        self.refresh()
        GLib.timeout_add(500, self.tick)
        self.window.present()

    def handle_key(self, _controller, keyval, _keycode, _state):
        if keyval == Gdk.KEY_Escape:
            self.window.close()
            return True
        if keyval == Gdk.KEY_space:
            self.control("play-pause")
            return True
        return False

    def control(self, action):
        player_cmd(action)
        GLib.timeout_add(150, self._refresh_once)

    def _refresh_once(self):
        self.refresh()
        return False

    def on_seek(self, _scale, _scroll, value):
        # value is in seconds; playerctl position sets absolute position
        player_cmd("position", f"{value:.2f}")
        self.user_seeking = True
        GLib.timeout_add(400, self._clear_seeking)
        return False

    def _clear_seeking(self):
        self.user_seeking = False
        return False

    def tick(self):
        if self.window is None or not self.window.get_visible():
            return False
        self.refresh()
        return True

    def refresh(self):
        status = out(["playerctl", "-p", PLAYER, "status"])
        if not status or status == "Stopped":
            self.body.set_visible(False)
            self.empty_label.set_visible(True)
            return
        self.body.set_visible(True)
        self.empty_label.set_visible(False)

        meta = out([
            "playerctl", "-p", PLAYER, "metadata", "--format",
            "{{title}}\t{{artist}}\t{{album}}\t{{mpris:artUrl}}\t{{mpris:length}}\t{{position}}",
        ])
        parts = meta.split("\t")
        while len(parts) < 6:
            parts.append("")
        title, artist, album, art_url, length_s, position_s = parts[:6]

        self.track_title.set_text(title or "Unknown")
        self.track_artist.set_text(artist or "Unknown")
        self.track_album.set_text(album or "")
        self.play_button.set_label("" if status == "Playing" else "")

        try:
            self.length = int(length_s) if length_s else 0
        except ValueError:
            self.length = 0
        try:
            position = int(position_s) if position_s else 0
        except ValueError:
            position = 0

        length_sec = self.length / 1_000_000 if self.length else 1
        self.scale.set_range(0, max(length_sec, 1))
        if not self.user_seeking:
            self.scale.set_value(position / 1_000_000)
        self.pos_label.set_text(fmt_time(position))
        self.len_label.set_text(fmt_time(self.length))

        if art_url and art_url != self.current_art_url:
            self.current_art_url = art_url
            self.load_art(art_url)

    def load_art(self, url):
        path = os.path.join(ART_DIR, hashlib.md5(url.encode()).hexdigest() + ".img")
        if os.path.exists(path):
            self.set_art(path)
            return

        def worker():
            try:
                if url.startswith("file://"):
                    src = url[len("file://"):]
                    with open(src, "rb") as fh:
                        data = fh.read()
                else:
                    with urllib.request.urlopen(url, timeout=8) as resp:
                        data = resp.read()
                with open(path, "wb") as fh:
                    fh.write(data)
                GLib.idle_add(lambda: self.set_art(path) or False)
            except Exception:
                pass

        threading.Thread(target=worker, daemon=True).start()

    def set_art(self, path):
        try:
            pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, 280, 280, True)
            self.art.set_from_pixbuf(pixbuf)
        except Exception:
            pass


SpotifyCenter().run([sys.argv[0]])
