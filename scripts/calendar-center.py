#!/usr/bin/env python3

import calendar
import datetime as dt
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
  padding: 14px 16px 8px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.08);
}

.month {
  font-size: 14px;
  font-weight: 700;
  color: #ffffff;
  letter-spacing: 0.5px;
}

.date {
  color: rgba(255, 255, 255, 0.45);
  font-size: 10px;
  letter-spacing: 0.3px;
}

.nav {
  min-width: 24px;
  min-height: 24px;
  padding: 0 6px;
  border-radius: 4px;
  background: transparent;
  border: none;
  color: rgba(255, 255, 255, 0.55);
  font-size: 12px;
  font-weight: 600;
  box-shadow: none;
}

.nav:hover {
  background: rgba(255, 255, 255, 0.06);
  color: #ffffff;
}

.calendar {
  padding: 10px 16px 16px;
}

.weekday {
  color: rgba(255, 255, 255, 0.30);
  font-size: 9px;
  font-weight: 700;
  letter-spacing: 0.5px;
  padding: 4px 0;
}

.day {
  background: transparent;
  border: none;
  border-radius: 4px;
  min-width: 36px;
  min-height: 32px;
  color: rgba(255, 255, 255, 0.85);
  font-size: 11px;
  font-weight: 500;
}

.muted {
  color: rgba(255, 255, 255, 0.18);
}

.today {
  background: #ffffff;
  color: #000000;
  font-weight: 700;
}
"""


class CalendarCenter(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="local.hypr.CalendarCenter")
        today = dt.date.today()
        self.year = today.year
        self.month = today.month
        self.today = today
        self.window = None
        self.title = None
        self.subtitle = None
        self.grid = None

    def do_activate(self):
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS.encode())
        display = Gdk.Display.get_default()
        if display is None:
            print("Calendar needs a graphical display.", file=sys.stderr)
            self.quit()
            return
        Gtk.StyleContext.add_provider_for_display(display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        self.window = Gtk.ApplicationWindow(application=self)
        self.window.set_title("Calendar Center")
        self.window.set_default_size(380, 400)
        self.window.set_resizable(False)
        self.window.set_decorated(False)

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        root.add_css_class("root")
        self.window.set_child(root)

        topbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        topbar.add_css_class("topbar")
        root.append(topbar)

        heading = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        heading.set_hexpand(True)
        self.title = Gtk.Label(xalign=0)
        self.title.add_css_class("month")
        self.subtitle = Gtk.Label(xalign=0)
        self.subtitle.add_css_class("date")
        heading.append(self.title)
        heading.append(self.subtitle)
        topbar.append(heading)

        for label, callback in (("<", self.prev_month), ("o", self.go_today), (">", self.next_month), ("x", self.close)):
            button = Gtk.Button(label=label)
            button.add_css_class("nav")
            button.connect("clicked", callback)
            topbar.append(button)

        self.grid = Gtk.Grid(column_spacing=2, row_spacing=2)
        self.grid.add_css_class("calendar")
        self.grid.set_column_homogeneous(True)
        root.append(self.grid)

        key = Gtk.EventControllerKey()
        key.connect("key-pressed", self.handle_key)
        self.window.add_controller(key)

        self.render()
        self.window.present()

    def handle_key(self, _controller, keyval, _keycode, _state):
        if keyval == Gdk.KEY_Escape:
            self.window.close()
            return True
        return False

    def clear_grid(self):
        child = self.grid.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            self.grid.remove(child)
            child = nxt

    def render(self):
        self.clear_grid()
        current = dt.date(self.year, self.month, 1)
        self.title.set_text(current.strftime("%B %Y").upper())
        self.subtitle.set_text(self.today.strftime("%a %d %b %Y").lower())

        for col, name in enumerate(("M", "T", "W", "T", "F", "S", "S")):
            label = Gtk.Label(label=name)
            label.add_css_class("weekday")
            self.grid.attach(label, col, 0, 1, 1)

        weeks = calendar.Calendar(firstweekday=0).monthdatescalendar(self.year, self.month)
        for row, week in enumerate(weeks, start=1):
            for col, day in enumerate(week):
                label = Gtk.Label(label=str(day.day))
                label.add_css_class("day")
                if day.month != self.month:
                    label.add_css_class("muted")
                if day == self.today:
                    label.add_css_class("today")
                self.grid.attach(label, col, row, 1, 1)

    def prev_month(self, *_):
        self.month -= 1
        if self.month == 0:
            self.month = 12
            self.year -= 1
        self.render()

    def next_month(self, *_):
        self.month += 1
        if self.month == 13:
            self.month = 1
            self.year += 1
        self.render()

    def go_today(self, *_):
        self.year = self.today.year
        self.month = self.today.month
        self.render()

    def close(self, *_):
        self.window.close()


CalendarCenter().run([sys.argv[0]])
