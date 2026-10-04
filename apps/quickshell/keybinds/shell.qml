//@ pragma UseQApplication

// Keybinding cheat sheet — SUPER+I.
//
// One glass card holding every bind in this rice, grouped into columns.
// The list is not hardcoded: scripts/keybinds-dump.py parses hypr.conf (and
// everything it sources) on each open, so a bind added to the config shows up
// here without touching this file.
//
// Blur comes from the `hypr-keybinds` layerrule in hypr.conf; the surface is
// fullscreen but transparent outside the card, and ignore_alpha keeps the
// frost off those pixels.
//
// Run:    qs -p ~/.config/hypr/apps/quickshell/keybinds
// Toggle: qs -p ~/.config/hypr/apps/quickshell/keybinds ipc call keybinds toggle

import QtQuick
import Quickshell
import "shared"
import Quickshell.Wayland
import Quickshell.Io

ShellRoot {
    id: root

    // ---- geometry ----
    readonly property int cardMaxWidth: 1180
    readonly property int headerHeight: 68
    readonly property int cardRadius: 22
    readonly property int pad: 22
    readonly property int columns: 3
    readonly property int rowSpacing: 7
    readonly property int capHeight: 22

    // ---- macOS Sonoma glass material ----
    readonly property color glass: Theme.glass
    readonly property color edge: Theme.edge
    readonly property color chip: Theme.chip
    readonly property color fg: Theme.fg
    readonly property color muted: Theme.muted
    readonly property color faint: Theme.faint
    // Selection and "on" states are a solid white fill, so anything drawn on
    // top of one has to invert to black to stay legible. (Named accentFg, not
    // onAccent — QML reads a property starting with "on" as a signal handler.)
    readonly property color accent: Theme.accent
    readonly property color accentFg: Theme.accentFg
    readonly property color accentFgMuted: Theme.accentFgMuted
    // Hover on a white fill has to go darker — Qt.lighter("#ffffff") is a no-op.
    readonly property color accentHover: Theme.accentHover
    // Falls back to Noto Sans until inter-font is installed.
    readonly property string uiFont: Theme.uiFont
    readonly property string iconFont: Theme.iconFont

    property bool shown: false
    property string query: "work"
    // Raw sections from the dump script: [{ title, items: [{ keys, action }] }]
    property var sections: []

    // .../hypr — this config lives at hypr/apps/quickshell/keybinds.
    readonly property string riceDir: Quickshell.shellPath("../../..")

    // ---- filtering ----
    // A row matches on its description or on any of its chords, so "super w"
    // and "firefox" both find the same line.
    function matches(item, q) {
        if (String(item.action).toLowerCase().indexOf(q) !== -1) return true;
        for (let i = 0; i < item.keys.length; i++) {
            if (item.keys[i].join(" ").toLowerCase().indexOf(q) !== -1) return true;
        }
        return false;
    }

    readonly property var filtered: {
        const q = query.trim().toLowerCase();
        const out = [];
        for (let i = 0; i < sections.length; i++) {
            const s = sections[i];
            const items = q === "" ? s.items : s.items.filter(it => matches(it, q));
            if (items.length > 0) out.push({ title: s.title, items: items });
        }
        return out;
    }

    readonly property int hitCount: {
        let n = 0;
        for (let i = 0; i < filtered.length; i++) n += filtered[i].items.length;
        return n;
    }

    // ---- column balancing ----
    // Greedy shortest-column packing over an estimated height (title + rows),
    // so three ragged columns end up roughly level instead of one long one.
    readonly property var buckets: {
        const cols = [];
        const weights = [];
        for (let c = 0; c < columns; c++) { cols.push([]); weights.push(0); }

        for (let i = 0; i < filtered.length; i++) {
            let best = 0;
            for (let c = 1; c < columns; c++) {
                if (weights[c] < weights[best]) best = c;
            }
            cols[best].push(filtered[i]);
            weights[best] += filtered[i].items.length + 2;
        }
        return cols;
    }

    function close() {
        shown = false;
        query = "";
    }

    // Re-read the config on every open: edit a bind, reopen, see it.
    Process {
        id: dump
        command: ["python3", root.riceDir + "/scripts/keybinds-dump.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.sections = JSON.parse(text);
                } catch (e) {
                    root.sections = [];
                }
            }
        }
    }

    IpcHandler {
        target: "keybinds"
        function toggle(): void {
            if (root.shown) root.close();
            else root.open();
        }
        function open(): void { root.open() }
        function close(): void { root.close() }
        function isOpen(): bool { return root.shown }
    }

    function open() {
        dump.running = true;
        shown = true;
    }

    PanelWindow {
        id: panel

        visible: root.shown || card.opacity > 0.01
        color: "transparent"

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "hypr-keybinds"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        onVisibleChanged: if (visible) input.forceActiveFocus()

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            id: card

            width: Math.min(root.cardMaxWidth, parent.width - 80)
            height: Math.min(root.headerHeight + body.height + root.pad, parent.height - 80)
            anchors.centerIn: parent

            radius: root.cardRadius
            color: root.glass
            border.width: 1
            border.color: root.edge
            clip: true

            opacity: root.shown ? 1 : 0
            scale: root.shown ? 1 : 0.98
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            // Swallow clicks so they never reach the dismiss layer underneath.
            MouseArea { anchors.fill: parent }

            // ---- header: title, search, count ----
            Item {
                id: header
                width: parent.width
                height: root.headerHeight

                Text {
                    id: title
                    anchors.left: parent.left
                    anchors.leftMargin: root.pad + 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Keyboard Shortcuts"
                    color: root.fg
                    font.family: root.uiFont
                    font.pixelSize: 19
                    font.weight: Font.DemiBold
                }

                Text {
                    id: magnifier
                    anchors.left: title.right
                    anchors.leftMargin: 28
                    anchors.verticalCenter: parent.verticalCenter
                    // \uF002 = nf-fa-search. Escaped, not pasted: a literal
                    // PUA codepoint does not survive every write path.
                    text: "\uF002"
                    color: root.faint
                    font.family: root.iconFont
                    font.pixelSize: 15
                }

                TextInput {
                    id: input

                    anchors.left: magnifier.right
                    anchors.leftMargin: 12
                    anchors.right: counter.left
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter

                    text: root.query
                    onTextChanged: root.query = text

                    color: root.fg
                    selectionColor: root.accent
                    selectedTextColor: root.accentFg
                    font.family: root.uiFont
                    font.pixelSize: 15
                    clip: true
                    focus: true

                    Keys.onEscapePressed: root.close()
                    Keys.onReturnPressed: root.close()

                    Text {
                        anchors.fill: parent
                        visible: input.text === ""
                        verticalAlignment: Text.AlignVCenter
                        text: "Filter shortcuts…"
                        color: root.faint
                        font: input.font
                    }
                }

                Text {
                    id: counter
                    anchors.right: parent.right
                    anchors.rightMargin: root.pad + 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.hitCount + (root.hitCount === 1 ? " binding" : " bindings")
                    color: root.faint
                    font.family: root.uiFont
                    font.pixelSize: 12
                }
            }

            // Hairline under the header — the only internal edge.
            Rectangle {
                y: root.headerHeight
                width: parent.width
                height: 1
                color: root.edge
            }

            // ---- body: balanced columns of groups ----
            Flickable {
                id: scroller
                y: root.headerHeight + 1
                width: parent.width
                height: Math.min(body.height + root.pad, card.height - root.headerHeight - 1)
                contentHeight: body.height + root.pad
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: body
                    x: root.pad
                    y: root.pad - 6
                    width: card.width - root.pad * 2
                    spacing: root.pad

                    Repeater {
                        model: root.buckets

                        Column {
                            id: column
                            required property var modelData

                            width: (body.width - root.pad * (root.columns - 1)) / root.columns
                            spacing: 18

                            Repeater {
                                model: column.modelData

                                Column {
                                    id: group
                                    required property var modelData

                                    width: column.width
                                    spacing: root.rowSpacing

                                    Text {
                                        text: group.modelData.title.toUpperCase()
                                        color: root.faint
                                        font.family: root.uiFont
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        font.letterSpacing: 1.2
                                        bottomPadding: 2
                                    }

                                    Repeater {
                                        model: group.modelData.items

                                        // One shortcut: chip cluster on the
                                        // left, what it does on the right.
                                        Item {
                                            id: row
                                            required property var modelData

                                            width: group.width
                                            height: Math.max(chords.height, label.implicitHeight)

                                            Row {
                                                id: chords
                                                anchors.left: parent.left
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 5

                                                Repeater {
                                                    model: row.modelData.keys

                                                    Row {
                                                        id: chord
                                                        required property int index
                                                        required property var modelData

                                                        spacing: 5

                                                        // Separates alternative
                                                        // chords for one action.
                                                        Text {
                                                            visible: chord.index > 0
                                                            height: root.capHeight
                                                            verticalAlignment: Text.AlignVCenter
                                                            text: "\u00B7"
                                                            color: root.faint
                                                            font.family: root.uiFont
                                                            font.pixelSize: 12
                                                        }

                                                        Repeater {
                                                            model: chord.modelData

                                                            Rectangle {
                                                                id: cap
                                                                required property string modelData

                                                                width: keycap.implicitWidth + 14
                                                                height: root.capHeight
                                                                radius: 6
                                                                color: root.chip
                                                                border.width: 1
                                                                border.color: root.edge

                                                                Text {
                                                                    id: keycap
                                                                    anchors.centerIn: parent
                                                                    text: cap.modelData
                                                                    color: root.fg
                                                                    font.family: root.uiFont
                                                                    font.pixelSize: 11
                                                                    font.weight: Font.Medium
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            Text {
                                                id: label
                                                anchors.left: chords.right
                                                anchors.leftMargin: 10
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                horizontalAlignment: Text.AlignRight
                                                text: row.modelData.action
                                                color: root.muted
                                                font.family: root.uiFont
                                                font.pixelSize: 12
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---- empty state ----
            Text {
                anchors.centerIn: parent
                visible: root.hitCount === 0
                text: root.sections.length === 0
                    ? "Could not read the keybindings"
                    : "No shortcut matches “" + root.query + "”"
                color: root.faint
                font.family: root.uiFont
                font.pixelSize: 14
            }
        }
    }
}
