//@ pragma UseQApplication

// App launcher — macOS Spotlight.
//
// One glass card: it starts as just the search field and grows downward as
// results arrive, the way Spotlight does. Blur comes from the `hypr-launcher`
// layerrule in hypr.conf; the surface itself is fullscreen but fully
// transparent outside the card, and ignore_alpha keeps the frost off those
// pixels.
//
// Run:    qs -p ~/.config/hypr/apps/quickshell/launcher
// Toggle: qs -p ~/.config/hypr/apps/quickshell/launcher ipc call launcher toggle

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Widgets

ShellRoot {
    id: root

    // ---- geometry ----
    readonly property int cardWidth: 760
    readonly property int fieldHeight: 64
    readonly property int rowHeight: 56
    readonly property int listMaxHeight: 380     // card tops out around 450
    readonly property int cardRadius: 20
    readonly property int topFraction: 20        // % of screen height above the card

    // ---- macOS Sonoma glass material ----
    readonly property color glass: Qt.rgba(30 / 255, 30 / 255, 30 / 255, 0.35)
    readonly property color edge: Qt.rgba(1, 1, 1, 0.18)
    readonly property color hover: Qt.rgba(1, 1, 1, 0.08)
    readonly property color fg: Qt.rgba(1, 1, 1, 0.95)
    readonly property color muted: Qt.rgba(1, 1, 1, 0.70)
    readonly property color faint: Qt.rgba(1, 1, 1, 0.45)
    readonly property color accent: "#0A84FF"
    // Falls back to Noto Sans until inter-font is installed.
    readonly property string uiFont: "Inter"
    readonly property string iconFont: "IosevkaTerm Nerd Font"

    property bool shown: false
    property string query: ""
    property int selected: 0

    // ---- matching ----
    // Ranked rather than plain substring: exact name beats prefix beats
    // word-start beats a hit buried in the description, so typing "fir" puts
    // Firefox above anything that merely mentions it.
    function rank(entry, q) {
        const name = (entry.name || "").toLowerCase();
        if (name === q) return 0;
        if (name.startsWith(q)) return 1;

        const words = name.split(/[\s\-_.]+/);
        for (let i = 0; i < words.length; i++) {
            if (words[i].startsWith(q)) return 2;
        }
        if (name.indexOf(q) !== -1) return 3;

        if (String(entry.genericName || "").toLowerCase().indexOf(q) !== -1) return 4;
        if (String(entry.keywords || "").toLowerCase().indexOf(q) !== -1) return 5;
        if (String(entry.comment || "").toLowerCase().indexOf(q) !== -1) return 6;
        return -1;
    }

    readonly property var results: {
        const q = query.trim().toLowerCase();
        if (q === "") return [];

        const out = [];
        const all = DesktopEntries.applications.values;
        for (let i = 0; i < all.length; i++) {
            const e = all[i];
            if (e.noDisplay) continue;
            const r = rank(e, q);
            if (r >= 0) out.push({ entry: e, rank: r });
        }

        out.sort((a, b) => a.rank !== b.rank
            ? a.rank - b.rank
            : (a.entry.name || "").localeCompare(b.entry.name || ""));

        return out.slice(0, 60).map(x => x.entry);
    }

    onResultsChanged: selected = 0

    function close() {
        shown = false;
        query = "";
        selected = 0;
    }

    function move(delta) {
        if (results.length === 0) return;
        selected = (selected + delta + results.length) % results.length;
        list.positionViewAtIndex(selected, ListView.Contain);
    }

    function launch() {
        if (results.length === 0 || selected >= results.length) return;
        results[selected].execute();
        close();
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void {
            if (root.shown) root.close();
            else root.shown = true;
        }
        function open(): void { root.shown = true }
        function close(): void { root.close() }
        function isOpen(): bool { return root.shown }
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
        WlrLayershell.namespace: "hypr-launcher"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        onVisibleChanged: if (visible) input.forceActiveFocus()

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        // One card: search on top, results grow underneath the divider.
        Rectangle {
            id: card

            width: root.cardWidth
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * root.topFraction / 100

            height: root.fieldHeight + (resultsBox.height > 0 ? resultsBox.height + 1 : 0)
            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            radius: root.cardRadius
            color: root.glass
            border.width: 1
            border.color: root.edge
            clip: true

            // Fade with a slight scale-in; nothing bouncy.
            opacity: root.shown ? 1 : 0
            scale: root.shown ? 1 : 0.98
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            // Swallow clicks so they never reach the dismiss layer underneath.
            MouseArea { anchors.fill: parent }

            // ---- search field ----
            Item {
                id: field
                width: parent.width
                height: root.fieldHeight

                Text {
                    id: magnifier
                    anchors.left: parent.left
                    anchors.leftMargin: 24
                    anchors.verticalCenter: parent.verticalCenter
                    // \uF002 = nf-fa-search. Escaped, not pasted: a literal PUA
                    // codepoint does not survive every write path, and a
                    // silently emptied glyph is invisible in review.
                    text: "\uF002"
                    color: root.faint
                    font.family: root.iconFont
                    font.pixelSize: 19
                }

                TextInput {
                    id: input

                    anchors.left: magnifier.right
                    anchors.leftMargin: 16
                    anchors.right: parent.right
                    anchors.rightMargin: 24
                    anchors.verticalCenter: parent.verticalCenter

                    text: root.query
                    onTextChanged: root.query = text

                    color: root.fg
                    selectionColor: root.accent
                    selectedTextColor: "#ffffff"
                    font.family: root.uiFont
                    font.pixelSize: 20
                    clip: true
                    focus: true

                    Keys.onUpPressed: root.move(-1)
                    Keys.onDownPressed: root.move(1)
                    Keys.onEscapePressed: root.close()
                    Keys.onReturnPressed: root.launch()
                    Keys.onEnterPressed: root.launch()

                    Text {
                        anchors.fill: parent
                        visible: input.text === ""
                        verticalAlignment: Text.AlignVCenter
                        text: "Spotlight Search"
                        color: root.faint
                        font: input.font
                    }
                }
            }

            // Hairline between search and results — the only internal edge.
            Rectangle {
                y: root.fieldHeight
                width: parent.width
                height: 1
                color: root.edge
                visible: resultsBox.height > 0
            }

            // ---- results ----
            Item {
                id: resultsBox
                y: root.fieldHeight + 1
                width: parent.width
                height: root.results.length === 0
                    ? 0
                    : Math.min(root.results.length * root.rowHeight + 12, root.listMaxHeight)

                ListView {
                    id: list
                    anchors.fill: parent
                    anchors.topMargin: 6
                    anchors.bottomMargin: 6
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    model: root.results
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    currentIndex: root.selected

                    delegate: Rectangle {
                        id: row

                        required property int index
                        required property var modelData

                        width: list.width
                        height: root.rowHeight

                        readonly property bool active: row.index === root.selected

                        radius: 12
                        // Subtle hover highlight; the selected row gets a
                        // restrained accent tint rather than a hard fill.
                        color: row.active
                            ? Qt.rgba(10 / 255, 132 / 255, 255 / 255, 0.28)
                            : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }

                        IconImage {
                            id: icon
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            implicitSize: 36
                            asynchronous: true
                            source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                        }

                        Column {
                            anchors.left: icon.right
                            anchors.leftMargin: 16
                            anchors.right: hint.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                width: parent.width
                                text: row.modelData.name
                                color: root.fg
                                font.family: root.uiFont
                                font.pixelSize: 15
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                visible: text !== ""
                                text: row.modelData.comment || row.modelData.genericName || ""
                                color: root.muted
                                font.family: root.uiFont
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            id: hint
                            anchors.right: parent.right
                            anchors.rightMargin: 18
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.active
                            text: "↵"
                            color: root.muted
                            font.family: root.iconFont
                            font.pixelSize: 15
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.selected = row.index
                            onClicked: { root.selected = row.index; root.launch() }
                        }
                    }
                }
            }
        }
    }
}
