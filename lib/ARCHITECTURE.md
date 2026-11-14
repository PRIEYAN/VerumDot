# Dependency injection, reuse and SOLID review

Reviewed the Bash module dependency graph and entry points, Python helpers,
Quickshell services and panel composition, installer boundary, and Neovim module
layout. This is an architectural review, not a claim that every hardware path
or UI interaction has been executed.

## Findings addressed

| Finding | Effect | Change |
| --- | --- | --- |
| PrivacyService constructed its own inspector/store/randomiser and called a static launcher | A fake command runner could still access sysfs, state files or launch a browser | Explicit collaborator injection; real adapters assembled in `python/hyprrice/composition.py` |
| PrivacyService mixed MAC operations, HTTP parsing and browser installation | Changes to unrelated features affected one class | Tor checking and browser operations moved to `python/hyprrice/tor.py`; service coordinates workflows |
| Concrete types and truthiness defaults constrained replacement collaborators | Independent or falsey implementations could be discarded | Narrow structural protocols; `None` selects defaults |
| Command ignored an explicitly empty environment and detach bypassed it | Tests and child processes could inherit unintended host settings | Shared environment semantics and command-error contract |
| Network inspection read a fixed sysfs path and raised raw read errors | Verification failures could bypass MAC rollback | Injectable network directory; expected inspection failures become `RiceError` |
| Power and fan imported each other | Policy could not be reused without loading the whole workflow | Shared `domain/powerprofile.sh`; fan policy extracted into pure `fan::resolve_pwm` |
| Power cached the requested mode before checking backend success | Failed operations could look successful and trigger notifications | Cache and dependent actions happen only after a successful backend call |
| Audio repaint masked the backend return status | Callers could not distinguish failed hardware changes | Preserve failure codes and repaint only on success |

Existing shell command names, power constants, CLI actions and JSON response
shapes remain available. The Python `PrivacyService` constructor now takes
explicit keyword dependencies; the CLI uses the production factory.

## Remaining findings and deliberate boundaries

| Area | Assessment / next useful change |
| --- | --- |
| Quickshell control centre | `apps/quickshell/controlcenter/shell.qml` still combines Wi-Fi, Bluetooth, audio, power policy and presentation. Extract native service adapters with injected properties/signals before trying to reuse those features in another panel. This needs real Wayland interaction tests. |
| QML process services | `BrightnessService.qml` emits `changed()` immediately after starting a write, despite its comment promising completion. Fan and brightness writes need success/failure and rapid-slider tests before a reusable asynchronous command component is introduced. |
| Notification coupling | Several Bash domain modules still import `ui/notify` or `ui/waybar`. Power profile access is now independent; other workflows should move notification decisions to their callers when another UI needs them. No global service locator or event bus is needed just to remove imports. |
| Waybar signal numbers | `shared/services/WaybarBridge.qml`, `lib/ui/waybar.sh` and Waybar config repeat the mapping. Add a consistency test or generate the adapters from one mapping before changing signal assignments. |
| Profile widgets | `apps/waybar/scripts/profile-timer.sh` and `profile-todos.sh` still contain persistence and behavior. Extract domain functions if another client needs them; `os/jsonstore.sh` already supplies reusable storage. |
| Installer | The installer is intentionally standalone for bootstrap. It combines wizard, discovery, package and deployment steps. Keep its deployment tests; extracting code must not make the one-file bootstrap depend on files that have not been cloned yet. The installer-only fix already pushed to main is separate from this review. |
| Neovim | Lua modules expose `setup()` and compose in `verum/init.lua`; this is appropriate for editor adapters. Inject `vim` only if extracting reusable logic outside Neovim, rather than wrapping every editor API. |
| Module loader | `hypr::use` marks a module loaded before sourcing and does not roll back that marker if sourcing fails. The dependency graph is now acyclic, but loader-failure semantics remain a separate hardening task. |
| Shell process fallback | `proc::first_available` splits command strings on whitespace. Current audio candidates use simple tokens. If reused for filenames or free-form user arguments, replace that API with argument arrays; do not add `eval`. |
| Splash startup | Deferred branch work; no splash QML, startup scripts, Hyprland config, or process-lock implementation changed in this review. |

## How SOLID applies here

- **Single responsibility:** separate policy, system access, UI rendering and
  application assembly. Size alone does not decide whether a module is wrong.
- **Open/closed:** replace a collaborator through an existing small contract;
  avoid editing a workflow merely to test or swap its system backend.
- **Liskov substitution:** replacements preserve outputs, errors and side-effect
  ordering. Tests exercise independent fake implementations, including rollback.
- **Interface segregation:** command readers need `run`, classifiers need
  `classify`, and formatters need `chord`. Do not require unrelated process/UI APIs.
- **Dependency inversion:** workflows receive collaborators; production assembly
  owns concrete adapters. In Bash, pure functions and replaceable module functions
  provide this boundary without an object/class framework.

No inheritance hierarchy, DI container, or repository-wide rewrite is necessary.
The remaining findings mean this is not a declaration of complete SOLID compliance.

## Validation

- 31 Python/contract/dependency tests passed with fake commands and temporary state.
- All 90 existing shared-library checks passed.
- Both suites also passed in Bubblewrap with the source and host tools read-only,
  an empty temporary home, and isolated network/process namespaces.
- The real privacy CLI returned its documented offline JSON shape in that sandbox;
  the keybind CLI returned valid sections from the checked-out config.
- All 92 shell files and 13 Python files passed syntax checks. The five changed
  shell files passed ShellCheck 0.11.0 with `-x`; shared public tables have targeted
  annotations for cross-module references.

No live MAC address, power mode, fan setting, audio device or package installation
was changed by the tests. Real hardware and graphical interaction remain untested.
