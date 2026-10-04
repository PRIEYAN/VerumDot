# lib — the shared library

Everything in `scripts/` and `apps/waybar/scripts/` is a thin entry point over
this directory. A script's job is to parse a verb and call into a module; the
behaviour lives here.

## Loading it

Every executable begins with the same three lines, at any depth:

```bash
_dir=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
while [ "$_dir" != "/" ] && [ ! -f "$_dir/lib/bootstrap.sh" ]; do _dir=$(dirname "$_dir"); done
source "$_dir/lib/bootstrap.sh"
```

The walk upwards is what makes the preamble identical everywhere. Before the
refactor there were three hand-maintained variants (`./`, `../`, `../../../`),
one per directory depth, and moving a script meant editing its preamble.

Then declare what you need:

```bash
hypr::use ui/rofi ui/notify domain/network
```

Modules load once, may declare their own dependencies, and may form a cycle
(`domain/power` and `domain/fan` genuinely need each other) — the loader marks
a module as loaded before sourcing it, so a cycle terminates.

## Layout

```
lib/
  bootstrap.sh     the only entry point; strict mode and the module loader
  core/
    paths.sh       every filesystem location, by meaning
    log.sh         diagnostics — on stderr, never stdout
    guard.sh       preconditions: has / require / one_of
    cli.sh         subcommand dispatch, usage and arity
    migrate.sh     one-shot move of pre-refactor state into os/state
  os/
    proc.sh        running commands, locks, single-instance popups
    state.sh       persisted scalars, validated at read
    jsonstore.sh   small JSON documents, written atomically
    hypr.sh        the compositor: hyprctl, sockets, the event stream
    symlink.sh     managed symlinks with one-shot backups
    ini.sh         idempotent edits to INI files other programs own
  ui/
    waybar.sh      the custom-module JSON protocol, and repaint signals
    rofi.sh        launching rofi: menus, prompts, toggles
    rofi_script.sh being launched *by* rofi (script mode)
    menu.sh        the streaming list dropdown shared by wifi/bluetooth
    notify.sh      desktop notifications
    markup.sh      Pango markup: escaping, meters, durations
    table.sh       the system-stats table
    theme.sh       colour tokens and thresholds
    appicons.sh    window class to Nerd Font glyph
    calendar.sh    month-grid construction
    quickshell.sh  toggling quickshell surfaces over IPC
    eww.sh         the remaining eww panels
  domain/
    audio.sh brightness.sh battery.sh bluetooth.sh eyecomfort.sh
    fan.sh network.sh player.sh power.sh session.sh sysstats.sh wallpaper.sh
  python/hyprrice/
    process.py errors.py cli.py privacy.py keybinds.py
```

`core` knows nothing about this rice. `os` wraps the system. `ui` renders.
`domain` models one piece of hardware or one service each. Dependencies point
downwards; nothing in `core` imports from `ui` or `domain`.

## Conventions

**stdout is a protocol.** Several of these scripts *are* an interface — a
waybar module's stdout must be one JSON object and a rofi menu's stdout is the
menu. Diagnostics therefore go through `log::*`, which writes to stderr. A
stray `echo` corrupts the caller.

**JSON is never built by hand.** `waybar::emit` goes through `jq`. The
previous hand-rolled `printf '{"text":"%s"...'` emitters produced invalid JSON
for any SSID or track title containing a quote or a backslash, and waybar
renders a blank module rather than complaining.

**Glyphs are codepoint escapes**, `$'\U000F0240'`, never pasted characters.
These are private-use Nerd Font codepoints; an editor or a copy/paste that
drops one leaves an empty string, and waybar *hides* a module whose text is
empty. A stripped glyph therefore deletes the module rather than degrading it.
This bit the original author (the Chrome icons) and it bit this refactor — see
the battery icons, which the test suite now guards.

**Keys, not labels.** Menu rows carry an explicit key (`ui/menu.sh`), so a
selection resolves by identity. The old menus re-parsed the rendered label to
recover the SSID or MAC, which broke on names containing the separator and on
two devices sharing a name.

**Enumerations are data.** Power modes, fan modes and battery thresholds are
arrays and tables, not chains of `elif`. Adding one is a line, not a branch.

## Tests

```bash
tests/run.sh          # everything
tests/run.sh markup   # matching test functions only
```

The suite is hermetic: tests that touch state run in a child shell with the
XDG directories pointed at a scratch dir, so running them can never disturb
the live wallpaper choice, fan mode or todo list. Tests that would need real
hardware assert on the pure logic instead — the parsing, clamping and
formatting, which is where the bugs actually were.
