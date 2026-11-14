# Hyprland: hyprlang → Lua config migration

Hyprland now reads a Lua config. When `~/.config/hypr/hyprland.lua` exists it
is loaded (`[cfg] Using lua config found at …`); `hyprland.conf` is only the
fallback when there is no Lua file. This document lists everything that
changed in this rice for that switch, and how to apply or undo it.

## The one command

```bash
~/.config/hypr/scripts/hyprland-lua-update.sh
```

It runs these steps in order. Each step has to pass before the next one runs:

| # | Step | On failure |
|---|------|------------|
| 1 | `sudo pacman -Syu --needed hyprland hyprlock hypridle hyprpaper hyprcursor hyprutils hyprlang aquamarine xdg-desktop-portal-hyprland hyprpolkitagent lua` (a full `-Syu`, because Arch does not support partial upgrades) | stops, nothing else changed |
| 2 | Checks that the installed Hyprland has the Lua engine | stops |
| 3 | `Hyprland --verify-config -c hyprland.lua`: Hyprland's own parser checks every module, field name, dispatcher argument and bezier | stops, live session untouched |
| 4 | `tests/test_keybinds.py`: the cheat sheet built from the Lua config must be **identical** to the one built from the old `hyprland.conf` | stops |
| 5 | `hyprctl reload full-reset` switches the running session to Lua without logging out | if the running binary will not switch, it tells you to re-login and leaves the legacy files alone |
| 6 | Moves `hyprland.conf`, `hypr.conf` and `workspaces.conf` to `legacy/`, only after Lua is live (hyprlang auto-reloads, so moving them earlier would strip a hyprlang session of its binds) | |
| 7 | Reloads waybar (`SIGUSR2`) and restarts hypridle so they pick up their edited configs | |

Options:

```bash
scripts/hyprland-lua-update.sh --check       # steps 2–4 only; changes nothing
scripts/hyprland-lua-update.sh --no-upgrade  # skip step 1
scripts/hyprland-lua-update.sh --rollback    # legacy/ back in place, hyprland.lua → .disabled, full-reset
```

Nothing is deleted. Running the script again after `--rollback` turns Lua back on.

## New layout

| Old (hyprlang) | New (Lua) | Contents |
|---|---|---|
| `hyprland.conf` | `hyprland.lua` | entry point; `require`s the modules below in the old order |
| top of `hypr.conf` (`$term`, `monitor =`, apps in binds) | `config/settings.lua` | per-machine choices: terminal, browser, files, editor, monitor, `nvidia`, `session_env`, `wallpaper_dir` |
| `env =` lines | `config/env.lua` | `hl.env(...)`; the NVIDIA line only applies when `settings.nvidia` is set |
| `monitor =`, `workspaces.conf` | `config/monitors.lua` | `hl.monitor{}`, then workspaces 1–9 persistent via `hl.workspace_rule{}` |
| `general`, `decoration`, `animations`, `render`, `bezier`, `animation` | `config/look.lua` | `hl.config{}`, `hl.curve()`, `hl.animation()` with the same values |
| `gesture =`, `gestures {}` | `config/input.lua` | `hl.gesture{}`, with the 4-finger exec gestures as Lua functions |
| `layerrule`, `windowrule` | `config/rules.lua` | `hl.layer_rule{}`, `hl.window_rule{}`, one rule per app instead of one line per effect |
| `bind*`, `submap` | `config/binds.lua` | `hl.bind()`, `hl.define_submap()` |
| `exec-once` | `config/autostart.lua` | `hl.on("hyprland.start", …)` + `hl.exec_cmd()`; runs once per session, never on reload |
| — | `.luarc.json` | points lua-language-server at `/usr/share/hypr/stubs` for completion of `hl.*` |

## Syntax translation used

| hyprlang | Lua |
|---|---|
| `bind = SUPER CTRL, N, exec, cmd` | `hl.bind("SUPER + CTRL + N", hl.dsp.exec_cmd("cmd"))` |
| `bindel = , XF86AudioMute, …` | `hl.bind("XF86AudioMute", …, { locked = true, repeating = true })` |
| `bindl = , switch:on:Lid Switch, …` | `hl.bind("switch:on:Lid Switch", …, { locked = true })` |
| `bindm = SUPER, mouse:272, movewindow` | `hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })` |
| `bindm = SUPER, mouse:273, resizewindow` | `hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })` |
| `killactive` | `hl.dsp.window.close()` |
| `fullscreen` | `hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })` |
| `workspace, 3` / `+1` / `-1` | `hl.dsp.focus({ workspace = "3" })` / `"+1"` / `"-1"` |
| `movetoworkspace, 3` | `hl.dsp.window.move({ workspace = "3", follow = true })` |
| `focuswindow, next` / `previous` | `hl.dsp.window.cycle_next()` / `cycle_next({ next = false })` |
| `submap = calendar … submap = reset` | `hl.define_submap("calendar", function() … end)` |
| two binds on one key (exec + `submap, reset`) | one bind with a function that calls `hl.dispatch()` twice |
| `gesture = 4, up, dispatcher, exec, x` | `hl.gesture({ fingers = 4, direction = "up", action = function() hl.dispatch(hl.dsp.exec_cmd(x)) end })` |
| `bezier = sonoma, 0.22, 1.0, 0.36, 1.0` | `hl.curve("sonoma", { type = "bezier", points = { {0.22, 1.0}, {0.36, 1.0} } })` |
| `animation = windows, 1, 2, sonoma, popin 96%` | `hl.animation({ leaf = "windows", enabled = true, speed = 2, bezier = "sonoma", style = "popin 96%" })` (same speed unit, 100ms) |
| `windowrule = match:class X, move 100%-w-10 48` | `move = "monitor_w-window_w-10 48"` (the old `100%`/`w` shorthands are now named expressions) |
| `windowrule = …, border_color A B` (active, inactive) | two rules, `match = { …, focus = true }` → A and `focus = false` → B |
| `layerrule = match:namespace ^(waybar)$, blur true` + `ignore_alpha 0.2` | `hl.layer_rule({ match = { namespace = "^(waybar)$" }, blur = true, ignore_alpha = 0.2 })` |

## Runtime IPC changes (scripts, waybar, hypridle, quickshell)

Under Lua, `hyprctl dispatch` takes a Lua expression
(`hyprctl dispatch 'hl.dsp.focus({ workspace = "3" })'`), and `hyprctl keyword`
has been replaced by `hyprctl eval '<lua>'`. So every
`hyprctl dispatch workspace 1` in the rice would have broken.

All compositor commands already went through `lib/os/hypr.sh`, and that file
now detects the live engine (`hyprctl eval` answers `ok` only under Lua) and
sends the matching syntax. Scripts therefore work before the switch, after it,
and after a rollback.

| Where | Before | Now |
|---|---|---|
| `lib/os/hypr.sh` | raw `dispatch`/`keyword` wrappers | `hypr::is_lua`, `hypr::dispatch_lua`, `hypr::set_option`, `hypr::dpms`, `hypr::monitor`, `hypr::exit`; `goto_workspace`, `toggle_special` and `set_shader`/`clear_shader` are engine-aware |
| `scripts/lid-close.sh` | `hypr::dispatch dpms off` | `hypr::dpms off` |
| `scripts/display-restore.sh` | `hypr::keyword monitor "$LINE"` + `dispatch dpms on` | `hypr::monitor out mode pos scale` + `hypr::dpms on` (`HYPR_MONITOR_LINE` still accepted) |
| `lib/domain/power.sh` | `exec hyprctl dispatch exit` | `hypr::exit` |
| `apps/quickshell/controlcenter/shell.qml` (logout) | `hyprctl dispatch exit` | `scripts/power-menu.sh logout` (new subcommand) |
| `apps/hypridle/hypridle.conf` | `hyprctl dispatch dpms off/on` | `scripts/dpms.sh off/on` (new) |
| `apps/waybar/config.jsonc` (14 workspace buttons) | `hyprctl dispatch workspace N` | `scripts/goto-workspace.sh N` (new) |

hypridle, hyprlock and hyprpaper are separate programs and keep their own
hyprlang configs. Only Hyprland itself moved to Lua.

## Cheat sheet (SUPER+I)

`scripts/keybinds-dump.py` used to regex-parse `bind =` lines. Now it reads
`hyprland.lua` by running it through `lib/lua/hl-recorder.lua`, which executes
the config against a stub `hl` that records each `hl.bind()`. Loops, `require`s
and function binds resolve exactly as Hyprland resolves them, and autostart
hooks never run. The recorder hands back legacy dispatcher names, so
`BindClassifier` did not change. The `.conf` reader is still there for
`legacy/hyprland.conf`. This needs the `lua` package (added to setup.sh's core
list).

## setup.sh

- `personalise()` now edits `config/settings.lua`, one anchored `key = value,`
  line per pick, instead of `sed`-ing bind lines in `hypr.conf`. The eww
  autostart checks for eww at runtime, so it no longer needs commenting out.
  The NVIDIA env, session environment and wallpaper folder are settings flags.
- After personalising, it runs `Hyprland --verify-config` on the result.
- The final "reload now?" prompt uses `hyprctl reload full-reset` when the live
  session is still on hyprlang, since a plain reload never switches engines.

## Small behaviour notes

- **SUPER+TAB / SUPER+SHIFT+TAB** now use `hl.dsp.window.cycle_next`, the
  documented dispatcher for cycling. The old line passed `next` to
  `focuswindow`, which takes a window selector.
- **eww daemon**: launched with `command -v eww && …`, so it is skipped quietly
  when eww is not installed.
- **`monitors.conf`** (written by nwg-displays) was never sourced by the old
  config and is still not used. The effective monitor is the one in
  `config/settings.lua`, as before (`eDP-1, preferred, auto, 1.0`).
- Everything else keeps the same values: gaps, blur, opacities, rules,
  animations, gestures and binds.

## How this was verified

- `Hyprland --verify-config -c hyprland.lua` reports `config ok`. Planting bad
  fields, dispatcher arguments and bezier names confirmed that the check
  catches them.
- The cheat sheet generated from the Lua config is byte-identical to the one
  generated from the old `hyprland.conf` (all 58 rows). This is kept as a test.
- `lib/os/hypr.sh` was exercised against a fake `hyprctl` in both engine modes
  to check the exact command strings, and its Lua expressions passed
  `--verify-config`.
- Migrate → rollback → migrate was run on a scratch copy of the repo.
- The `tests/run.sh` suite (90 checks) and all `tests/test_*.py` pass.

## Editing from now on

```bash
$EDITOR ~/.config/hypr/config/binds.lua                    # or any module
Hyprland --verify-config -c ~/.config/hypr/hyprland.lua    # check before reloading
hyprctl reload
hyprctl dispatch 'hl.dsp.focus({ workspace = "2" })'       # ad-hoc dispatch syntax
hyprctl eval 'hl.config({ decoration = { rounding = 10 } })'  # replaces `hyprctl keyword`
```

Reference: the wiki source at `github.com/hyprwm/hyprland-wiki`
(`content/configuring/…`), plus `/usr/share/hypr/hyprland.lua` and
`/usr/share/hypr/stubs/hl.meta.lua`, which ship with the package.
