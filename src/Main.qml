import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 1360
    height: 860
    minimumWidth: 560
    minimumHeight: 520
    visible: true
    title: "Fireteam"
    color: Style.bg

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius

    // Hyprland tiles windows, so the board has to read in a narrow column too.
    readonly property bool narrow: width < 1100
    readonly property bool overlayOpen: briefing.visible || help.visible || confirm.visible
    readonly property var selected: roster.currentItem

    function move(step) {
        if (roster.count > 0)
            roster.currentIndex = Math.max(0, Math.min(roster.count - 1, roster.currentIndex + step))
    }
    function deploySelected() { if (selected) ops.deploy(roster.currentIndex) }
    function abortSelected() {
        if (!selected || selected.status !== "deployed")
            return
        const row = roster.currentIndex
        confirm.ask(qsTr("Abort %1?").arg(selected.codename),
                    qsTr("The agent is stopped mid-cycle. Files it already changed stay changed."),
                    qsTr("Abort"), () => ops.abort(row))
    }
    function removeSelected() {
        if (!selected || selected.status === "deployed")
            return
        const row = roster.currentIndex
        confirm.ask(qsTr("Stand down %1?").arg(selected.codename),
                    qsTr("The operation, its comms and its debriefs are deleted from Fireteam. The project itself isn't touched."),
                    qsTr("Stand down"), () => ops.remove(row))
    }
    function quit() {
        if (ops.deployedCount > 0)
            confirm.ask(qsTr("Pull out?"),
                        qsTr("%n agent(s) still deployed. Quitting stops them mid-cycle; you can resume later.", "", ops.deployedCount),
                        qsTr("Quit"), () => Qt.quit())
        else
            Qt.quit()
    }

    onClosing: (close) => {
        if (ops.deployedCount > 0 && !confirm.visible) {
            close.accepted = false
            quit()
        }
    }

    Shortcut { sequences: ["?", "Shift+?"]; context: Qt.ApplicationShortcut; enabled: !briefing.visible && !confirm.visible; onActivated: help.visible = !help.visible }
    Shortcut { sequence: "Q"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: win.quit() }
    Shortcut { sequence: "N"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: briefing.open() }
    Shortcut { sequence: "Space"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: win.deploySelected() }
    Shortcut { sequence: "X"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: win.abortSelected() }
    Shortcut { sequence: "R"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: ops.openLatestReport(roster.currentIndex) }
    Shortcut { sequence: "D"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: ops.openDossier(roster.currentIndex) }
    Shortcut { sequence: "O"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: ops.openProject(roster.currentIndex) }
    Shortcut { sequence: "Delete"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: win.removeSelected() }
    Shortcut { sequences: ["Down", "J"]; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: win.move(1) }
    Shortcut { sequences: ["Up", "K"]; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: win.move(-1) }
    Shortcut {
        sequence: "Esc"
        context: Qt.ApplicationShortcut
        enabled: win.overlayOpen
        onActivated: {
            if (confirm.visible) confirm.visible = false
            else if (help.visible) help.visible = false
            else briefing.close()
        }
    }

    // Takes keyboard focus back from a closed panel's text fields, which would
    // otherwise swallow the single-key shortcuts.
    Item { id: board; focus: true }

    TacticalBackdrop {
        anchors.fill: parent
        accent: theme.accent
        active: win.visibility !== Window.Minimized
    }

    // Right-to-left languages mirror the window; the Translator sets the
    // application's layout direction.
    Item {
        anchors.fill: parent
        LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
        LayoutMirroring.childrenInherit: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: win.narrow ? 18 : 32
            anchors.bottomMargin: 20
            spacing: 18

            // Header: the title on the left, the link and the clock on the right.
            RowLayout {
                Layout.fillWidth: true
                spacing: 24
                Rectangle { implicitWidth: 6; implicitHeight: 64; color: theme.accent }
                ColumnLayout {
                    spacing: 0
                    Text {
                        id: brand
                        text: "FIRETEAM"
                        color: Style.text
                        font.family: Style.display
                        font.pixelSize: 46
                        font.weight: Font.Black
                        font.letterSpacing: 12
                        // An occasional flicker, like a menu waking up.
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            PauseAnimation { duration: 5200 }
                            NumberAnimation { to: 0.4; duration: 40 }
                            NumberAnimation { to: 1; duration: 60 }
                            NumberAnimation { to: 0.6; duration: 30 }
                            NumberAnimation { to: 1; duration: 80 }
                        }
                    }
                    Text {
                        text: qsTr("Base camp  //  operations board")
                        color: Style.dim
                        font.family: Style.mono
                        font.pixelSize: 12
                        font.letterSpacing: 4
                        font.capitalization: Font.AllUppercase
                    }
                }
                Item { Layout.fillWidth: true }

                ColumnLayout {
                    visible: win.width > 820
                    spacing: 4
                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: qsTr("Claude link")
                        color: Style.dim
                        font.family: Style.display
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        font.letterSpacing: 3
                        font.capitalization: Font.AllUppercase
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: 8
                        Rectangle {
                            implicitWidth: 8; implicitHeight: 8; radius: 4
                            color: ops.linkStatus === "online" ? Style.good : ops.linkStatus === "checking" ? Style.amber : Style.danger
                        }
                        Text {
                            text: ops.linkStatus === "online" ? qsTr("Online · %1").arg(ops.account)
                                : ops.linkStatus === "checking" ? qsTr("Checking…")
                                : ops.linkStatus === "missing" ? qsTr("claude not installed")
                                : qsTr("Not logged in: run claude to sign in")
                            color: ops.linkStatus === "online" ? Style.text : Style.danger
                            font.family: Style.mono
                            font.pixelSize: 12
                        }
                    }
                }
                Rectangle { visible: win.width > 820; implicitWidth: 1; implicitHeight: 44; color: Style.line }
                ColumnLayout {
                    spacing: 0
                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: qsTr("Deployed")
                        color: Style.dim
                        font.family: Style.display
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        font.letterSpacing: 3
                        font.capitalization: Font.AllUppercase
                    }
                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: Style.pad(ops.deployedCount) + " / " + Style.pad(roster.count)
                        color: ops.deployedCount > 0 ? theme.accent : Style.text
                        font.family: Style.mono
                        font.pixelSize: 24
                        font.bold: true
                    }
                }
                Rectangle { visible: !win.narrow; implicitWidth: 1; implicitHeight: 44; color: Style.line }
                Text {
                    id: clock
                    visible: !win.narrow
                    text: Qt.formatTime(new Date(), "HH:mm:ss")
                    color: Style.text
                    font.family: Style.mono
                    font.pixelSize: 24
                    Timer { interval: 1000; running: true; repeat: true; onTriggered: clock.text = Qt.formatTime(new Date(), "HH:mm:ss") }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: win.narrow ? 16 : 32

                // The roster of operations, as a game menu.
                ColumnLayout {
                    Layout.preferredWidth: win.narrow ? 260 : 380
                    Layout.maximumWidth: win.narrow ? 260 : 380
                    Layout.fillWidth: false
                    Layout.fillHeight: true
                    spacing: 10
                    SectionLabel { Layout.fillWidth: true; text: qsTr("Operations"); detail: Style.pad(roster.count) }
                    ListView {
                        id: roster
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: ops
                        currentIndex: count > 0 ? 0 : -1
                        highlightFollowsCurrentItem: false
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: RosterEntry { onActivated: roster.currentIndex = index }
                        add: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 300 }
                                NumberAnimation { property: "x"; from: -60; to: 0; duration: 340; easing.type: Easing.OutCubic }
                            }
                        }
                        displaced: Transition { NumberAnimation { properties: "y"; duration: 220; easing.type: Easing.OutCubic } }
                        ScrollBar.vertical: ScrollBar {}
                    }
                    TacticalButton {
                        Layout.fillWidth: true
                        text: qsTr("Plan operation")
                        key: "N"
                        primary: roster.count === 0
                        onClicked: briefing.open()
                    }
                }

                Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Style.line }

                OperationDetail {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    op: win.selected
                    row: roster.currentIndex
                    onDeployRequested: win.deploySelected()
                    onAbortRequested: win.abortSelected()
                    onRemoveRequested: win.removeSelected()
                }
            }

            // Footer: the controls, the way a game menu lists them.
            RowLayout {
                Layout.fillWidth: true
                spacing: 22
                KeyHint { key: "N"; label: qsTr("Plan") }
                KeyHint { key: qsTr("Space"); label: qsTr("Deploy") }
                KeyHint { visible: !win.narrow; key: "X"; label: qsTr("Abort") }
                KeyHint { visible: !win.narrow; key: "R"; label: qsTr("Debrief") }
                KeyHint { key: "?"; label: qsTr("Controls") }
                KeyHint { key: "Q"; label: qsTr("Quit") }
                Item { Layout.fillWidth: true }
                Text {
                    text: "FIRETEAM " + Qt.application.version
                    color: Style.faint
                    font.family: Style.mono
                    font.pixelSize: 11
                    font.letterSpacing: 2
                }
            }
        }

        NewOperationPanel {
            id: briefing
            anchors.fill: parent
            onVisibleChanged: if (!visible) board.forceActiveFocus()
            onPlanned: (deployNow) => {
                roster.currentIndex = 0
                if (deployNow)
                    ops.deploy(0)
            }
        }
        HelpOverlay { id: help; anchors.fill: parent }
        ConfirmPanel { id: confirm; anchors.fill: parent }
    }

    Scanlines { anchors.fill: parent }
}
