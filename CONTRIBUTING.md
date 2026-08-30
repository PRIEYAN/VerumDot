# Contributing to VerumDot

VerumDot is one person's daily driver that grew into a rice other people
install. Contributions are welcome — but the design is opinionated, so read
this first.

## The grammar

Every change should hold the line the rest of the config holds:

- **Pure black `#000000` panels.** Not `#0a0a0a`, not "very dark grey."
- **White type, white icons.** Selection inverts to black-on-white.
- **No accent colors.** No purple, no catppuccin, no rainbow workspace dots.
- **Glass over gloss.** Depth comes from blur and opacity, not borders and shadows.
- **Rofi, not eww,** for popups and menus. The eww panels are legacy and on
  their way out; new menus go through `apps/rofi/*.rasi`.

A PR that adds a color is not a small PR. Open an issue first.

## Practical rules

- **Portable paths.** Never hardcode `/home/prieyan`. Source
  `scripts/_paths.sh` and use `$HYPR_DIR`. A grep for your own username before
  you push is a good habit.
- **Shell scripts** are `#!/usr/bin/env bash`, and should pass
  `shellcheck -x`. Fail gracefully when a binary is missing — not everyone has
  `cpupower` or `hyprsunset`.
- **New dependency?** Add it to `packages.txt` *and* to the matching
  `pkgs_for` / `aur_for` group in `setup.sh`. The installer is the source of
  truth; `packages.txt` is the human-readable mirror.
- **Comment the non-obvious.** The existing scripts explain *why*
  (see the redshift-vs-hyprsunset note in `eye-comfort-toggle.sh`). Match that.

## Testing a change

```bash
./setup.sh --dry-run     # prints the plan, touches nothing
hyprctl reload           # reload the compositor after config edits
```

For installer changes, test in a VM or container if you can. `setup.sh` backs
up everything it replaces as `<path>.bak.<timestamp>`, but a fresh machine is
the only honest test.

## Screenshots

If your change is visual, put a screenshot in the PR. This is a rice — "looks
right" is a functional requirement.

## Commits

Plain, lowercase, descriptive. Look at `git log` and match it.
