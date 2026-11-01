# Login splash

`hyprland.conf` calls `scripts/splash.sh` independently of wallpaper, Waybar,
and the other session helpers. It never gates their startup.

The QML uses [Quickshell Variants](https://quickshell.org/docs/v0.3.2/types/Quickshell/Variants/)
to create one overlay per connected output. Initialization happens while the
windows are hidden. A shared timer then controls every output: wait at least
320ms, start an early fade when desktop layers are ready, and hide at the 850ms
ceiling. The 180ms fade is included in the display budget. It fades the black
background too; the window itself is transparent.

Readiness means `hyprctl -j layers` contains nonzero, visible `hyprpaper` and
`waybar` surfaces on every reported output. That is stronger than a process or
socket existing, but does not claim to inspect the wallpaper's pixels. Each IPC
probe is bounded, probes never overlap, and failed probes cannot extend the
animation deadline.

Windows unmap before requesting Qt shutdown. The launcher allows up to four
seconds for cold initialization plus animation/cleanup, then sends TERM and
escalates to KILL after 500ms. The animation's visible budget is independent of
that process budget; on the tested laptop cold Qt startup took about two seconds.
The timers are scheduler deadlines, not hard real-time guarantees.

The launcher disables desktop-portal activation and uses
[Qt's CPU-decoding configuration](https://doc.qt.io/qt-6/advanced-ffmpeg-configuration.html#configure-hardware-acceleration-in-backends)
for this short clip, avoiding optional portal/GPU-decoder initialization work.
These settings are scoped to the splash process. There is no AudioOutput, so the
video's audio track is silent. Qt documents the decoder environment switch as
private API; retest it after Qt upgrades.

A per-session lock plus Quickshell's no-duplicate flag prevents stacked overlays.
The timeout manages its own child process group and never kills the other
Quickshell panels. Media and QML errors are retained in
`${XDG_CACHE_HOME:-~/.cache}/hypr/splash.log`; the launcher returns successfully
so an optional animation cannot abort login.

## Tests

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p test_splash.py -v
```

Ten tests cover mapped-layer readiness on multiple outputs, invisible layers,
malformed/stalled IPC, missing prerequisites, error logs, duplicate launches,
forced decoder cleanup, delayed compositor startup, and Waybar restart/termination.
They use fake processes and private state; they never change real desktop services.
The supervisor tests need an environment that permits local Unix sockets.

The optional graphical test requires Sway, Quickshell, grim and Mesa software
OpenGL. It starts its own headless compositor with two virtual monitors, uses
controlled Hyprland readiness replies, and captures only the private test desktop:

```bash
python3 tests/splash_wayland.py
```

`SWAY_BIN` can point to an extracted Sway binary. `SPLASH_TEST_ARTIFACTS` selects
the output directory (default `/tmp/verumdot-splash-wayland`). Run it in a
Bubblewrap/container environment with a private home/runtime tree for maximum
isolation. It checks actual decoded video, both overlays, the fade to a colored
background, early readiness dismissal, and malformed-media cleanup. The Sway
fixture validates Wayland layer-shell behavior; it is not a second Hyprland login.

Validation also included a bounded preview in the existing Hyprland session:
QML loaded, the real readiness probe reported `desktop ready`, and the overlay
hid before the launcher exited successfully. No full logout/reboot was performed.
