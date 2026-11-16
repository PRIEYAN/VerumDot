# Installer update implementation plan

**Goal:** Add an update choice to the existing bootstrap and setup wizard.

**Design:** Reuse deployment, package and theme setup. Save a versioned JSON record outside the rice containing selected groups/apps, requested packages and configured services. Updates load those choices, check installed packages, install only missing requirements, and retain Arch's full-upgrade transaction when repository packages are missing. Keep per-machine settings by merging old single-line settings into new defaults. Always back up deployment before replacing files. Retired recorded packages/services are offered individually, default no, without recursive dependency removal. Untracked older installations establish a baseline without guessing removals.

**Files:** install.sh, setup.sh, README.md, tests/test_installer_update.py.

**Constraints:** Never execute saved state as shell code. Never remove packages in unattended runs. Never run the installer against the development machine during verification. Keep existing user edits.

## Tasks

- [x] Add tests for missing-only installation, retained choices, retired-package approval and service retirement.
- [x] Add --update and wizard choice, state persistence and package reconciliation.
- [x] Add service catalogue and explicit retirement prompts; preserve machine settings during deployment.
- [x] Document update commands and first-update limitations.
- [x] Run installer tests, library tests, Python tests, shell syntax and diff checks. Review destructive paths and failure handling.

## Verification and review

- 58 Python tests passed, including 13 update lifecycle checks and 2 existing AUR stdin checks.
- 90 shared-library checks passed; shell syntax and git diff whitespace checks passed.
- Bootstrap --update --dry-run accepted without fetching or writing.
- Real deployment exercised inside temporary config/state/wallpaper directories: old files backed up, latest files copied, Waybar/QML links repaired, machine settings retained.
- Independent review identified legacy app-choice adoption and config-only optional-service regressions. Both were fixed and covered by tests; follow-up review found no additional important issues.
- Package manager and service actions were stubbed. No real package transactions or service changes were performed.

Implementation decisions: Updates preserve supported application choices from the existing settings before computing dependencies, even for installations without records. Package transactions run in the foreground with confirmations visible. Retired service cleanup runs before enabling current services. Work stayed in the shared checkout; no commits or GitHub pushes were made.
