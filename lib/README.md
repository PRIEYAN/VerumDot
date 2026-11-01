# lib — the shared library

Shared behavior belongs here. Entry points in `scripts/` and
`apps/waybar/scripts/` parse verbs and assemble application workflows. Some
older menu/profile entry points still contain domain logic; see the
[architecture review](ARCHITECTURE.md) for the remaining boundaries.

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

Modules load once and declare their own dependencies. Keep the dependency
graph acyclic: `domain/fan` and `domain/power` both use `domain/powerprofile`,
while only the power workflow calls the fan policy. The loader guards duplicate
loads; that guard is not a reason to introduce a dependency cycle.

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
    fan.sh network.sh player.sh power.sh powerprofile.sh session.sh sysstats.sh wallpaper.sh
  python/hyprrice/
    process.py errors.py cli.py privacy.py tor.py composition.py keybinds.py
```

`core` provides paths, logging, guards and dispatch. `os` wraps system access;
`ui` renders. Hardware/domain modules provide reusable operations; a few also
coordinate UI notifications. Neither `core` nor `os` imports `ui` or `domain`,
and the tests enforce that dependency direction.

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

## Dependency injection and reuse

Python workflows accept small structural `Protocol` interfaces. A replacement
only implements the methods its caller needs; it does not subclass a concrete
system adapter. `composition.create_privacy_service()` constructs production
adapters and injects them into `PrivacyService`. Browser launch, executable
lookup, command execution, network inspection, profile storage and IP checking
can all be replaced without contacting the real system. The CLI and QML JSON
formats are unchanged. Direct Python callers now construct `PrivacyService`
with its keyword dependencies, or use `create_privacy_service()`.

`ConfigReader` accepts a `Classifier` and `ChordFormatter`. Optional dependency
defaults check `is None`, preserving valid objects whose boolean value is false.
`Command(env={})` uses the empty environment plus `LC_ALL=C`; it does not inherit
the host environment accidentally. Detached commands use the same environment.

Bash uses functions and modules instead of artificial classes. Keep policy pure
when possible (`fan::resolve_pwm setting power_mode`). Tests replace named
system-boundary functions such as `proc::quiet`, then exercise the real workflow.
Power/audio operations return failures before updating dependent state or
repainting the UI. Add behavior tests whenever a shared function's error or
side-effect contract changes.

## Tests

```bash
tests/run.sh          # everything
tests/run.sh markup   # matching test functions only
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_*.py' -v
```

The suite is hermetic: tests that touch state run in a child shell with the
XDG directories pointed at a scratch dir, so running them can never disturb
the live wallpaper choice, fan mode or todo list. Tests that would need real
hardware assert on the pure logic instead — the parsing, clamping and
formatting, which is where the bugs actually were.
