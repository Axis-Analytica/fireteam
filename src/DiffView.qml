import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// What one cycle changed: its files on the left, the selected file's diff on
// the right, read from the snapshots taken around the cycle.
Item {
    id: view
    visible: false
    property var op: null
    property int row: -1
    property int run: -1
    property var files: []
    property int fileIndex: 0
    property var lines: []
    readonly property var entry: op && run >= 0 && run < op.history.length ? op.history[run] : null
    readonly property bool hasIntel: entry !== null && entry.before.length > 0 && entry.after.length > 0
    // Long diffs are cut here; the full diff is a git command away.
    readonly property int lineLimit: 4000

    signal rollbackRequested(int run)

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius

    function open(target, targetRow, targetRun) {
        op = target
        row = targetRow
        visible = true
        enter.restart()
        show(targetRun)
    }
    function show(targetRun) {
        if (!op || targetRun < 0 || targetRun >= op.history.length)
            return
        run = targetRun
        files = ops.cycleChanges(row, run)
        pick(0)
    }
    function pick(index) {
        fileIndex = Math.max(0, Math.min(files.length - 1, index))
        if (files.length === 0) {
            lines = []
            return
        }
        const all = ops.cycleDiff(row, run, files[fileIndex].path).split("\n")
        lines = all.length > lineLimit ? all.slice(0, lineLimit).concat([qsTr("… %1 more lines").arg(all.length - lineLimit)]) : all
        diff.positionViewAtBeginning()
        fileList.positionViewAtIndex(fileIndex, ListView.Contain)
    }
    function close() { visible = false }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.82)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: view.close() }
    }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(1280, parent.width - 48)
        height: parent.height - 48
        color: Qt.rgba(0.035, 0.043, 0.055, 0.98)
        border.color: Style.line
        radius: theme.radius
        // Clicks on the panel itself mustn't reach the dismissing backdrop.
        MouseArea { anchors.fill: parent }
        Rectangle { width: parent.width; height: 3; color: theme.accent }

        ParallelAnimation {
            id: enter
            NumberAnimation { target: sheet; property: "opacity"; from: 0; to: 1; duration: 160 }
            NumberAnimation { target: sheet; property: "scale"; from: 0.98; to: 1; duration: 220; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 18
                ColumnLayout {
                    spacing: 2
                    Text {
                        text: view.op ? qsTr("Intel // %1").arg(view.op.codename) : ""
                        color: theme.accent
                        font.family: Style.mono
                        font.pixelSize: 11
                        font.letterSpacing: 4 * Style.tracking
                        font.capitalization: Font.AllUppercase
                    }
                    Text {
                        text: view.entry ? qsTr("Cycle %1").arg(Style.pad(view.entry.cycle)) : ""
                        color: Style.text
                        font.family: Style.display
                        font.pixelSize: 34
                        font.weight: Font.Black
                        font.letterSpacing: 5 * Style.tracking
                        font.capitalization: Font.AllUppercase
                    }
                }
                Text {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: 6
                    text: !view.entry ? ""
                        : qsTr("Run %1 of %2 · session %3 · %n file(s)", "", view.files.length)
                              .arg(view.run + 1).arg(view.op.history.length).arg(view.entry.session)
                          + (view.hasIntel ? "  +" + view.entry.added + " −" + view.entry.removed : "")
                    elide: Text.ElideRight
                    color: Style.dim
                    font.family: Style.mono
                    font.pixelSize: 12
                }
                TacticalButton { text: "◂"; key: "["; enabled: view.run > 0; onClicked: view.show(view.run - 1) }
                TacticalButton {
                    text: "▸"; key: "]"
                    enabled: view.op && view.run < view.op.history.length - 1
                    onClicked: view.show(view.run + 1)
                }
            }

            Text {
                Layout.fillWidth: true
                visible: view.entry !== null && view.entry.sitrep.length > 0
                text: view.entry ? view.entry.sitrep : ""
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: Style.text
                font.family: Style.display
                font.pixelSize: 13
                textFormat: Text.PlainText
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 14
                visible: view.hasIntel && view.files.length > 0

                ListView {
                    id: fileList
                    Layout.preferredWidth: Math.min(340, sheet.width * 0.3)
                    Layout.fillHeight: true
                    clip: true
                    model: view.files
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}
                    delegate: Item {
                        id: fileRow
                        required property var modelData
                        required property int index
                        readonly property bool chosen: index === view.fileIndex
                        width: ListView.view.width - 10
                        height: 30
                        Rectangle {
                            anchors.fill: parent
                            color: fileRow.chosen ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.16)
                                 : fileHover.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                            radius: Math.min(4, theme.radius)
                        }
                        Rectangle { visible: fileRow.chosen; width: 3; height: parent.height; color: theme.accent }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 8
                            spacing: 8
                            Text {
                                text: fileRow.modelData.status
                                color: fileRow.modelData.status === "A" ? Style.good
                                     : fileRow.modelData.status === "D" ? Style.danger : theme.accent
                                font.family: Style.mono
                                font.pixelSize: 12
                                font.bold: true
                            }
                            Text {
                                Layout.fillWidth: true
                                text: fileRow.modelData.path
                                elide: Text.ElideMiddle
                                color: fileRow.chosen ? Style.text : Style.dim
                                font.family: Style.mono
                                font.pixelSize: 12
                            }
                            Text {
                                text: fileRow.modelData.binary ? qsTr("bin")
                                    : "<font color=\"" + Style.good + "\">+" + fileRow.modelData.added + "</font> <font color=\""
                                      + Style.danger + "\">−" + fileRow.modelData.removed + "</font>"
                                textFormat: Text.StyledText
                                color: Style.dim
                                font.family: Style.mono
                                font.pixelSize: 11
                            }
                        }
                        HoverHandler { id: fileHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: view.pick(fileRow.index) }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Qt.rgba(0, 0, 0, 0.5)
                    border.color: Style.line
                    radius: theme.radius
                    ListView {
                        id: diff
                        anchors.fill: parent
                        anchors.margins: 10
                        clip: true
                        model: view.lines
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {}
                        delegate: Rectangle {
                            id: diffLine
                            required property string modelData
                            readonly property string kind: modelData.startsWith("@@") ? "hunk"
                                : modelData.startsWith("+++") || modelData.startsWith("---")
                                  || modelData.startsWith("diff ") || modelData.startsWith("index ")
                                  || modelData.startsWith("new file") || modelData.startsWith("deleted file") ? "meta"
                                : modelData.startsWith("+") ? "add"
                                : modelData.startsWith("-") ? "del" : "same"
                            width: ListView.view.width - 12
                            height: lineText.implicitHeight + 2
                            color: kind === "add" ? Qt.rgba(Style.good.r, Style.good.g, Style.good.b, 0.09)
                                 : kind === "del" ? Qt.rgba(Style.danger.r, Style.danger.g, Style.danger.b, 0.1)
                                 : "transparent"
                            Text {
                                id: lineText
                                width: parent.width - 8
                                x: 4
                                text: diffLine.modelData.length > 0 ? diffLine.modelData : " "
                                wrapMode: Text.WrapAnywhere
                                textFormat: Text.PlainText
                                color: diffLine.kind === "add" ? Style.good
                                     : diffLine.kind === "del" ? Style.danger
                                     : diffLine.kind === "hunk" ? theme.accent
                                     : diffLine.kind === "meta" ? Style.faint : Style.dim
                                font.family: Style.mono
                                font.pixelSize: 12
                            }
                        }
                    }
                }
            }

            // Nothing to diff: say why.
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !(view.hasIntel && view.files.length > 0)
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 10
                    Crosshair { Layout.alignment: Qt.AlignHCenter }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: view.hasIntel ? qsTr("No files changed this cycle") : qsTr("No intel for this cycle")
                        color: Style.text
                        font.family: Style.display
                        font.pixelSize: 20
                        font.weight: Font.Black
                        font.letterSpacing: 4 * Style.tracking
                        font.capitalization: Font.AllUppercase
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        visible: !view.hasIntel
                        text: qsTr("Fireteam snapshots cycles in git repositories. Run git init in the project to get diffs and rollback.")
                        color: Style.dim
                        font.family: Style.display
                        font.pixelSize: 13
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                TacticalButton { text: qsTr("Close"); key: "Esc"; onClicked: view.close() }
                KeyHint { key: "J K"; label: qsTr("Files") }
                KeyHint { key: "[ ]"; label: qsTr("Cycles") }
                Item { Layout.fillWidth: true }
                TacticalButton {
                    visible: view.op !== null && view.op.canUndoRollback
                    text: qsTr("Undo rollback")
                    enabled: view.op !== null && view.op.status !== "deployed"
                    onClicked: ops.undoRollback(view.row)
                }
                TacticalButton {
                    text: view.entry ? qsTr("Roll back to before cycle %1").arg(view.entry.cycle) : ""
                    danger: true
                    enabled: view.hasIntel && view.op.status !== "deployed"
                    onClicked: view.rollbackRequested(view.run)
                }
            }
        }
    }

    Shortcut { enabled: view.visible; sequences: ["J", "Down"]; context: Qt.ApplicationShortcut; onActivated: view.pick(view.fileIndex + 1) }
    Shortcut { enabled: view.visible; sequences: ["K", "Up"]; context: Qt.ApplicationShortcut; onActivated: view.pick(view.fileIndex - 1) }
    Shortcut { enabled: view.visible && view.run > 0; sequence: "["; context: Qt.ApplicationShortcut; onActivated: view.show(view.run - 1) }
    Shortcut {
        enabled: view.visible && view.op !== null && view.run < view.op.history.length - 1
        sequence: "]"
        context: Qt.ApplicationShortcut
        onActivated: view.show(view.run + 1)
    }
    Shortcut { enabled: view.visible; sequences: ["PgDown", "Space"]; context: Qt.ApplicationShortcut; onActivated: diff.contentY = Math.min(diff.contentY + diff.height * 0.9, Math.max(0, diff.contentHeight - diff.height)) }
    Shortcut { enabled: view.visible; sequence: "PgUp"; context: Qt.ApplicationShortcut; onActivated: diff.contentY = Math.max(0, diff.contentY - diff.height * 0.9) }
}
