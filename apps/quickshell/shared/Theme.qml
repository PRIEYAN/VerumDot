pragma Singleton

// Theme — the macOS Sonoma glass design tokens, in one place.
//
// All four shells (control centre, spotify card, launcher, cheat sheet) used
// to declare their own copies of these colours and fonts. They were identical
// by convention only: a palette change meant four edits, and any one of them
// could be missed without anything failing loudly.
//
// Each shell still exposes the tokens it uses as its own aliases, so existing
// bindings keep working; only the *values* moved here.
//
// Quickshell refuses to load a module from outside a shell's own config
// folder, so each surface carries a `shared` symlink back to this directory.
// The symlink is the mechanism; this file is still the single definition.
//
// The shell-script side has the same tokens in lib/ui/theme.sh and the rofi
// themes carry them in apps/rofi/*.rasi — three surfaces, three languages, no
// shared format between them. These are the only places a colour is defined.

import QtQuick
import Quickshell

Singleton {
    // ---- material ----------------------------------------------------
    // The panel sits at 60% so white text stays legible over a bright
    // wallpaper; the compositor's blur supplies the frost behind it.
    readonly property color glass: Qt.rgba(28 / 255, 28 / 255, 30 / 255, 0.60)
    readonly property color edge: Qt.rgba(1, 1, 1, 0.18)

    // Cards layered on the glass use the 12% white "raised" material.
    readonly property color raised: Qt.rgba(1, 1, 1, 0.12)
    readonly property color tileOff: Qt.rgba(1, 1, 1, 0.12)
    readonly property color chip: Qt.rgba(1, 1, 1, 0.12)
    readonly property color trackOff: Qt.rgba(1, 1, 1, 0.18)

    readonly property color hover: Qt.rgba(1, 1, 1, 0.08)
    readonly property color pressed: Qt.rgba(1, 1, 1, 0.15)

    // ---- text --------------------------------------------------------
    readonly property color fg: Qt.rgba(1, 1, 1, 0.95)
    readonly property color muted: Qt.rgba(1, 1, 1, 0.70)
    readonly property color faint: Qt.rgba(1, 1, 1, 0.45)

    // ---- selection ---------------------------------------------------
    // "On" and selected states are a solid white fill, so anything drawn on
    // top of one has to invert to black.
    readonly property color accent: "#ffffff"
    readonly property color accentFg: "#000000"
    readonly property color accentFgMuted: Qt.rgba(0, 0, 0, 0.60)
    // Hover on a white fill must go *darker*: Qt.lighter("#ffffff") is a no-op.
    readonly property color accentHover: Qt.rgba(0.87, 0.87, 0.87, 1)

    readonly property color danger: "#FF6961"

    // ---- type --------------------------------------------------------
    // Falls back to Noto Sans until inter-font is installed.
    readonly property string uiFont: "Inter"
    readonly property string iconFont: "IosevkaTerm Nerd Font"

    // ---- shared geometry ---------------------------------------------
    // Only what every surface genuinely agrees on. Card radius and padding
    // deliberately stay local: the control centre and the cheat sheet use 22,
    // the spotify card and launcher 20, and that is a design choice per
    // surface rather than drift.
    readonly property int barHeight: 44      // waybar island: 4px margin + 40px

    // ---- motion ------------------------------------------------------
    // Sonoma easing: decelerate into place, never overshoot. Mirrors the
    // bezier curves hypr.conf defines for window animations.
    readonly property int fastMs: 150
    readonly property int normalMs: 220
}
