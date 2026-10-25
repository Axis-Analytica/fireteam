import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// The first-run checklist: what Fireteam leans on, whether this machine has
// it, and the fix for each gap in place. Required items first, then the
// optional ones that switch features on.
Item {
    id: panel
    visible: false
    signal terminalRequested()

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius
    Material.background: Style.panel

    // What ops.environment() last found; re-read on open, on "Check again"
    // and whenever graphify changes.
    property var env: ({})
    property string copied: ""

    function refresh() { env = ops.environment() }
    function open() {
        refresh()
        visible = true
        enter.restart()
        scroller.ScrollBar.vertical.position = 0
    }
    function close() { visible = false }
    function checkAgain() {
        refresh()
        ops.checkLink()
    }
    function copy(command) {
        clipboard.text = command
        clipboard.selectAll()
        clipboard.copy()
        copied = command
        copiedTimer.restart()
    }

    Connections {
        target: ops
        function onGraphsChanged() { if (panel.visible) panel.refresh() }
    }
    Timer { id: copiedTimer; interval: 1600; onTriggered: panel.copied = "" }
    // The clipboard is reached through a hidden editor.
    TextEdit { id: clipboard; visible: false }

    // ── Each item's state ───────────────────────────────────────────────
    readonly property string claudePath: env.claude || ""
    readonly property bool claudeInstalled: claudePath.length > 0 && ops.linkStatus !== "missing"
    readonly property bool claudeReady: claudeInstalled && ops.linkStatus === "online"
    readonly property string gitPath: env.git || ""
    readonly property string graphifyPath: ops.graphify.length > 0 ? ops.graphify : (env.graphify || "")
    readonly property string chromiumPath: env.chromium || ""
    readonly property string qrencodePath: env.qrencode || ""
    readonly property bool terminalOn: !!terminal && terminal.enabled
    readonly property bool terminalListening: !!terminal && terminal.enabled && terminal.listening

    readonly property int readyCount: (claudeReady ? 1 : 0) + (gitPath.length > 0 ? 1 : 0)
                                      + (graphifyPath.length > 0 ? 1 : 0) + (chromiumPath.length > 0 ? 1 : 0)
                                      + (qrencodePath.length > 0 ? 1 : 0) + (terminalListening ? 1 : 0)
    readonly property int requiredMissing: (claudeReady ? 0 : 1) + (gitPath.length > 0 ? 0 : 1)

    // A check: a square mark, the item and what it's for, what was found,
    // and the fix: a command to copy, or a control on the right.
    component CheckRow: RowLayout {
        id: row
        property string label
        property string hint
        property string status
        property color tone: Style.good
        property string command
        property string commandNote
        default property alias control: slot.data
        Layout.fillWidth: true
        spacing: 16

        Rectangle {
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 6
            implicitWidth: 8
            implicitHeight: 8
            color: row.tone
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3
            Text {
                Layout.fillWidth: true
                text: row.label
                wrapMode: Text.Wrap
                color: Style.text
                font.family: Style.body
                font.pixelSize: 14
                font.weight: Font.Medium
            }
            Text {
                Layout.fillWidth: true
                text: row.hint
                wrapMode: Text.Wrap
                color: Style.dim
                font.family: Style.body
                font.pixelSize: 12
                lineHeight: 1.15
            }
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 2
                visible: text.length > 0
                text: row.status
                elide: Text.ElideMiddle
                color: row.tone === Style.good ? Style.text2 : row.tone
                font.family: Style.mono
                font.variableAxes: Style.narrow
                font.pixelSize: 11
            }
            // The fix, as a command to run in a terminal.
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 6
                visible: row.command.length > 0
                implicitHeight: 34
                color: Style.bg
                border.color: Style.line
                radius: Math.min(2, theme.radius)
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 4
                    spacing: 10
                    Text {
                        text: "$"
                        color: theme.accent
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                        font.pixelSize: 12
                    }
                    Text {
                        Layout.fillWidth: true
                        text: row.command
                        elide: Text.ElideRight
                        color: Style.text
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                        font.pixelSize: 12
                    }
                    Rectangle {
                        id: copyButton
                        readonly property bool done: panel.copied === row.command
                        implicitWidth: copyLabel.implicitWidth + 20
                        implicitHeight: 26
                        color: copyHover.hovered ? Style.raised : "transparent"
                        border.color: copyHover.hovered ? Style.lineStrong : "transparent"
                        radius: Math.min(2, theme.radius)
                        Text {
                            id: copyLabel
                            anchors.centerIn: parent
                            text: copyButton.done ? qsTr("Copied") : qsTr("Copy")
                            color: copyButton.done ? Style.good : copyHover.hovered ? Style.text : Style.text2
                            font.family: Style.body
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        HoverHandler { id: copyHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: panel.copy(row.command) }
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: row.commandNote
                wrapMode: Text.Wrap
                color: Style.dim
                font.family: Style.body
                font.pixelSize: 12
            }
        }
        Item {
            id: slot
            Layout.alignment: Qt.AlignTop
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
        }
    }
    component Rule: Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Style.bg.r, Style.bg.g, Style.bg.b, 0.86)
        MouseArea { anchors.fill: parent; onClicked: panel.close() }
    }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(760, parent.width - 48)
        height: Math.min(840, parent.height - 32)
        color: Style.panel
        border.color: Style.lineStrong
        radius: theme.radius
        MouseArea { anchors.fill: parent }
        Brackets { anchors.fill: parent; anchors.margins: -1; size: 12 }

        ParallelAnimation {
            id: enter
            NumberAnimation { target: sheet; property: "opacity"; from: 0; to: 1; duration: 140 }
            NumberAnimation { target: sheet; property: "anchors.verticalCenterOffset"; from: 8; to: 0; duration: 140; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 16

            // ── Header: what this is, and how far along ─────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 20
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Text {
                        Layout.fillWidth: true
                        text: "# " + qsTr("Base camp").toLowerCase() + " // " + qsTr("Setup").toLowerCase()
                        elide: Text.ElideRight
                        color: Style.dim
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                        font.pixelSize: 11
                    }
                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Ready for deployment")
                        wrapMode: Text.Wrap
                        color: Style.text
                        font.family: Style.display
                        font.pixelSize: 28
                        font.weight: Font.DemiBold
                        font.letterSpacing: -0.6
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        text: qsTr("What Fireteam leans on, whether this machine has it, and the fix for anything missing.")
                        wrapMode: Text.Wrap
                        color: Style.text2
                        font.family: Style.body
                        font.pixelSize: 13
                        lineHeight: 1.2
                    }
                }
                Figure {
                    Layout.alignment: Qt.AlignTop
                    value: panel.readyCount + "/6"
                    comment: qsTr("Ready").toLowerCase()
                    size: 32
                }
            }

            // The verdict on the required items.
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                readonly property bool checking: panel.requiredMissing === 1 && panel.claudeInstalled
                                                 && ops.linkStatus === "checking"
                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 5
                    implicitWidth: 7
                    implicitHeight: 7
                    color: parent.checking ? Style.amber : panel.requiredMissing > 0 ? Style.danger : Style.good
                }
                Text {
                    Layout.fillWidth: true
                    text: parent.checking ? qsTr("Checking the Claude Code sign-in…")
                        : panel.requiredMissing === 2 ? qsTr("Two required items need attention before operations can deploy.")
                        : panel.requiredMissing === 1 ? qsTr("One required item needs attention before operations can deploy.")
                        : qsTr("Everything required is ready. The optional items switch on extra features and can wait.")
                    wrapMode: Text.Wrap
                    color: Style.text
                    font.family: Style.body
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
            }

            ScrollView {
                id: scroller
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                clip: true

                ColumnLayout {
                    width: scroller.availableWidth - 12
                    spacing: 11

                    SectionLabel {
                        Layout.fillWidth: true
                        text: qsTr("Required")
                        detail: (2 - panel.requiredMissing) + "/2"
                    }

                    CheckRow {
                        label: "Claude Code"
                        hint: qsTr("Runs every agent. Fireteam drives the claude command you already use.")
                        tone: panel.claudeReady ? Style.good
                            : panel.claudeInstalled && ops.linkStatus === "checking" ? Style.amber : Style.danger
                        status: !panel.claudeInstalled ? qsTr("Not installed")
                              : ops.linkStatus === "online" ? panel.claudePath + (ops.account.length > 0 ? " · " + ops.account : "")
                              : ops.linkStatus === "checking" ? panel.claudePath + " · " + qsTr("Checking sign-in…")
                              : panel.claudePath + " · " + qsTr("Not signed in")
                        command: !panel.claudeInstalled ? "omarchy-pkg-add claude-code"
                               : ops.linkStatus !== "online" && ops.linkStatus !== "checking" ? "claude" : ""
                        commandNote: !panel.claudeInstalled ? qsTr("Or with npm: npm install -g @anthropic-ai/claude-code. Then run claude once to sign in.")
                                   : command.length > 0 ? qsTr("Run it in a terminal, sign in, then check again.") : ""
                    }
                    Rule {}
                    CheckRow {
                        label: "git"
                        hint: qsTr("Snapshots, worktrees and extraction: each operation works on its own branch.")
                        tone: panel.gitPath.length > 0 ? Style.good : Style.danger
                        status: panel.gitPath.length > 0 ? panel.gitPath : qsTr("Not installed")
                        command: panel.gitPath.length > 0 ? "" : "omarchy-pkg-add git"
                    }

                    SectionLabel {
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        text: qsTr("Optional")
                        detail: (panel.readyCount - (2 - panel.requiredMissing)) + "/4"
                    }

                    CheckRow {
                        id: graphifyRow
                        readonly property bool installing: ops.graphifyInstall === "installing"
                        readonly property bool failed: ops.graphifyInstall.length > 0 && !installing
                        label: "graphify"
                        hint: qsTr("Knowledge graphs: maps a project's code locally, with no API key.")
                        tone: panel.graphifyPath.length > 0 ? Style.good : failed ? Style.danger : Style.amber
                        status: panel.graphifyPath.length > 0 ? panel.graphifyPath
                              : installing ? qsTr("Installing graphify…")
                              : failed ? ops.graphifyInstall : qsTr("Not installed")
                        ColumnLayout {
                            spacing: 6
                            visible: panel.graphifyPath.length === 0
                            TacticalButton {
                                enabled: !graphifyRow.installing
                                text: graphifyRow.failed ? qsTr("Try again") : qsTr("Install")
                                onClicked: ops.installGraphify()
                            }
                            // Stepped cells while it installs.
                            Row {
                                id: cells
                                property int lit: 0
                                Layout.alignment: Qt.AlignHCenter
                                visible: graphifyRow.installing
                                spacing: 2
                                Repeater {
                                    model: 8
                                    delegate: Rectangle {
                                        required property int index
                                        width: 6; height: 3
                                        color: index === cells.lit ? theme.accent : Style.line
                                    }
                                }
                                Timer {
                                    running: cells.visible && panel.visible
                                    repeat: true
                                    interval: 120
                                    onTriggered: cells.lit = (cells.lit + 1) % 8
                                }
                            }
                        }
                    }
                    Rule {}
                    CheckRow {
                        label: "Chromium"
                        hint: qsTr("Preview screenshots of the pages an operation changes.")
                        tone: panel.chromiumPath.length > 0 ? Style.good : Style.amber
                        status: panel.chromiumPath.length > 0 ? panel.chromiumPath : qsTr("Not installed")
                        command: panel.chromiumPath.length > 0 ? "" : "omarchy-pkg-add chromium"
                    }
                    Rule {}
                    CheckRow {
                        label: "qrencode"
                        hint: qsTr("Shows the field terminal's pairing code as a QR code to scan.")
                        tone: panel.qrencodePath.length > 0 ? Style.good : Style.amber
                        status: panel.qrencodePath.length > 0 ? panel.qrencodePath : qsTr("Not installed")
                        command: panel.qrencodePath.length > 0 ? "" : "omarchy-pkg-add qrencode"
                    }
                    Rule {}
                    CheckRow {
                        label: qsTr("Field terminal")
                        hint: qsTr("Steer operations from your phone: comms, questions, approvals and orders.")
                        tone: panel.terminalListening ? Style.good : Style.amber
                        status: !terminal ? qsTr("Unavailable")
                              : panel.terminalListening ? qsTr("On · listening")
                              : panel.terminalOn ? qsTr("On · not listening") : qsTr("Off")
                        TacticalButton {
                            text: qsTr("Set up")
                            enabled: !!terminal
                            onClicked: panel.terminalRequested()
                        }
                    }
                }
            }

            Rule {}
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                TacticalButton { text: qsTr("Check again"); onClicked: panel.checkAgain() }
                Item { Layout.fillWidth: true }
                TacticalButton { text: qsTr("Done"); key: "Esc"; primary: true; onClicked: panel.close() }
            }
        }
    }
}
