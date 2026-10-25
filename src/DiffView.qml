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
    // The gate whose output replaces the diff, by name, or "".
    property string gateOutput: ""
    readonly property var gateLines: {
        if (!entry || gateOutput === "") return []
        const gate = (entry.gates || []).find(g => g.name === gateOutput)
        return gate ? ("$ " + gate.command + "\n" + gate.output).split("\n") : []
    }
    readonly property var entry: op && run >= 0 && run < op.history.length ? op.history[run] : null
    readonly property bool hasIntel: entry !== null && entry.before.length > 0 && entry.after.length > 0
    // Old and new line numbers for each diff line, read from the hunk heads,
    // for the gutter.
    readonly property var numbers: {
        const out = []
        let a = 0, b = 0
        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i]
            const hunk = /^@@ -(\d+)(?:,\d+)? \+(\d+)/.exec(line)
            if (hunk) { a = parseInt(hunk[1]); b = parseInt(hunk[2]); out.push(["", ""]); continue }
            if ((a === 0 && b === 0) || (line === "" && i === lines.length - 1)) { out.push(["", ""]); continue }
            if (line.startsWith("+") && !line.startsWith("+++")) out.push(["", "" + b++])
            else if (line.startsWith("-") && !line.startsWith("---")) out.push(["" + a++, ""])
            else if (line.startsWith("\\")) out.push(["", ""])
            else out.push(["" + a++, "" + b++])
        }
        return out
    }
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
        gateOutput = ""
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
        color: Qt.rgba(Style.bg.r, Style.bg.g, Style.bg.b, 0.86)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: view.close() }
    }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(1280, parent.width - 48)
        height: parent.height - 48
        color: Style.panel
        border.color: Style.lineStrong
        radius: theme.radius
        // Clicks on the panel itself mustn't reach the dismissing backdrop.
        MouseArea { anchors.fill: parent }
        Brackets { anchors.fill: parent; anchors.margins: -1; size: 12 }

        ParallelAnimation {
            id: enter
            NumberAnimation { target: sheet; property: "opacity"; from: 0; to: 1; duration: 140 }
            NumberAnimation { target: sheet; property: "anchors.verticalCenterOffset"; from: 8; to: 0; duration: 140; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // The cycle, the proof gathered for it, and its sitrep.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 28
                Layout.rightMargin: 28
                Layout.topMargin: 24
                Layout.bottomMargin: 18
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 18
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Text {
                            Layout.fillWidth: true
                            text: view.op ? "# " + qsTr("Intel // %1").arg(view.op.codename) : ""
                            elide: Text.ElideRight
                            color: Style.dim
                            font.family: Style.mono
                            font.variableAxes: Style.narrow
                            font.pixelSize: 11
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 16
                            Text {
                                text: view.entry ? qsTr("Cycle %1").arg(Style.pad(view.entry.cycle)) : ""
                                color: Style.text
                                font.family: Style.display
                                font.pixelSize: 28
                                font.weight: Font.DemiBold
                                font.letterSpacing: -0.6
                            }
                            Text {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignBaseline
                                text: !view.entry ? ""
                                    : qsTr("Run %1 of %2 · session %3 · %n file(s)", "", view.files.length)
                                          .arg(view.run + 1).arg(view.op.history.length).arg(view.entry.session)
                                      + (view.hasIntel ? "  <font color=\"" + theme.accent + "\">+" + view.entry.added
                                                         + "</font> −" + view.entry.removed : "")
                                textFormat: Text.StyledText
                                elide: Text.ElideRight
                                color: Style.dim
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 11
                            }
                        }
                    }
                    TacticalButton { text: "◂"; key: "["; enabled: view.run > 0; onClicked: view.show(view.run - 1) }
                    TacticalButton {
                        text: "▸"; key: "]"
                        enabled: view.op && view.run < view.op.history.length - 1
                        onClicked: view.show(view.run + 1)
                    }
                }

                // Proof for this run: each gate (click for its output) and the
                // preview screenshot.
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: view.entry !== null && ((view.entry.gates || []).length > 0 || view.entry.screenshot !== undefined)
                    Repeater {
                        model: view.entry ? (view.entry.gates || []) : []
                        delegate: Rectangle {
                            id: gatePill
                            required property var modelData
                            readonly property bool shown: view.gateOutput === modelData.name
                            width: gateLabel.implicitWidth + 38
                            height: 28
                            color: shown ? Style.wash : gateHover.hovered ? Style.raised : Style.panel
                            border.color: shown ? theme.accent : Style.line
                            radius: Math.min(2, theme.radius)
                            Rectangle {
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: 6; height: 6
                                color: gatePill.modelData.passed ? Style.good : Style.danger
                            }
                            Text {
                                id: gateLabel
                                x: 26
                                anchors.verticalCenter: parent.verticalCenter
                                text: gatePill.modelData.name + "  <font color=\"" + Style.dim + "\">" + gatePill.modelData.seconds + "s</font>"
                                textFormat: Text.StyledText
                                color: gatePill.shown ? Style.text : Style.text2
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 11
                            }
                            HoverHandler { id: gateHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: view.gateOutput = gatePill.shown ? "" : gatePill.modelData.name }
                        }
                    }
                    TacticalButton {
                        height: 28
                        visible: view.entry !== null && view.entry.screenshot !== undefined
                        text: qsTr("Screenshot ↗")
                        onClicked: ops.openReport(view.entry.screenshot)
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: view.entry !== null && view.entry.sitrep.length > 0
                    text: view.entry ? view.entry.sitrep : ""
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    color: Style.text2
                    font.family: Style.body
                    font.pixelSize: 13
                    lineHeight: 1.15
                    textFormat: Text.PlainText
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 28
                Layout.topMargin: 18
                Layout.bottomMargin: 18
                spacing: 16
                visible: (view.hasIntel && view.files.length > 0) || view.gateOutput !== ""

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
                        height: 32
                        Rectangle {
                            anchors.fill: parent
                            color: fileRow.chosen ? Style.wash : fileHover.hovered ? Style.raised : "transparent"
                        }
                        Rectangle { visible: fileRow.chosen; width: 2; height: parent.height; color: theme.accent }
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width; height: 1
                            color: Style.line
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 8
                            spacing: 10
                            Text {
                                text: fileRow.modelData.status
                                color: fileRow.modelData.status === "A" ? theme.accent
                                     : fileRow.modelData.status === "D" ? Style.dim : Style.text2
                                font.family: Style.mono
                                font.variableAxes: Style.narrowMedium
                                font.pixelSize: 11
                            }
                            Text {
                                Layout.fillWidth: true
                                text: fileRow.modelData.path
                                elide: Text.ElideMiddle
                                color: fileRow.chosen ? Style.text : Style.text2
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 12
                            }
                            Text {
                                text: fileRow.modelData.binary ? qsTr("bin")
                                    : "<font color=\"" + theme.accent + "\">+" + fileRow.modelData.added + "</font> −" + fileRow.modelData.removed
                                textFormat: Text.StyledText
                                color: Style.dim
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 11
                                font.features: { "tnum": 1 }
                            }
                        }
                        HoverHandler { id: fileHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: view.pick(fileRow.index) }
                    }
                }

                // The diff, as Terminal draws one: a gutter of line numbers, a
                // marker column, removed lines dimmed, added ones on the wash.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Style.bg
                    border.color: Style.line
                    radius: Math.min(2, theme.radius)
                    TextMetrics {
                        id: digit
                        text: "0000"
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                        font.pixelSize: 11
                    }
                    ListView {
                        id: diff
                        anchors.fill: parent
                        anchors.margins: 1
                        anchors.topMargin: 8
                        anchors.bottomMargin: 8
                        clip: true
                        model: view.gateOutput !== "" ? view.gateLines : view.lines
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {}
                        delegate: Rectangle {
                            id: diffLine
                            required property string modelData
                            required property int index
                            readonly property bool gate: view.gateOutput !== ""
                            readonly property string kind: gate ? (index === 0 ? "command" : "same")
                                : modelData.startsWith("@@") ? "hunk"
                                : modelData.startsWith("+++") ? "head"
                                : modelData.startsWith("---")
                                  || modelData.startsWith("diff ") || modelData.startsWith("index ")
                                  || modelData.startsWith("new file") || modelData.startsWith("deleted file") ? "meta"
                                : modelData.startsWith("+") ? "add"
                                : modelData.startsWith("-") ? "del" : "same"
                            readonly property bool marked: kind === "add" || kind === "del" || kind === "command"
                                || (kind === "same" && !gate && modelData.startsWith(" "))
                            readonly property var number: !gate && index < view.numbers.length ? view.numbers[index] : ["", ""]
                            readonly property real gutter: gate ? 0 : digit.width * 2 + 28
                            width: ListView.view.width - 10
                            height: lineText.implicitHeight + (kind === "head" ? 8 : kind === "hunk" ? 10 : 2)
                            color: kind === "add" ? Style.wash : kind === "hunk" ? Style.panel : "transparent"
                            // The file header stands over a firmer line.
                            Rectangle {
                                visible: diffLine.kind === "head"
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 3
                                x: 8
                                width: parent.width - 16
                                height: 1
                                color: Style.lineStrong
                            }
                            Text {
                                visible: !diffLine.gate
                                x: 8
                                width: digit.width
                                y: lineText.y
                                horizontalAlignment: Text.AlignRight
                                text: diffLine.number[0]
                                color: Style.faint
                                font: digit.font
                            }
                            Text {
                                visible: !diffLine.gate
                                x: 8 + digit.width + 8
                                width: digit.width
                                y: lineText.y
                                horizontalAlignment: Text.AlignRight
                                text: diffLine.number[1]
                                color: Style.faint
                                font: digit.font
                            }
                            Text {
                                id: marker
                                x: diffLine.gutter + 8
                                y: lineText.y
                                text: diffLine.kind === "add" ? "+" : diffLine.kind === "del" ? "-" : diffLine.kind === "command" ? "$" : ""
                                color: diffLine.kind === "del" ? Style.dim : theme.accent
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 12
                            }
                            Text {
                                id: lineText
                                x: diffLine.gutter + 24
                                y: diffLine.kind === "hunk" ? 5 : diffLine.kind === "head" ? 0 : 1
                                width: parent.width - x - 8
                                text: {
                                    const body = diffLine.marked && !diffLine.gate ? diffLine.modelData.substring(1)
                                               : diffLine.kind === "command" ? diffLine.modelData.replace(/^\$ /, "")
                                               : diffLine.modelData
                                    return body.length > 0 ? body : " "
                                }
                                wrapMode: Text.WrapAnywhere
                                textFormat: Text.PlainText
                                color: diffLine.kind === "add" || diffLine.kind === "head" || diffLine.kind === "command" ? Style.text
                                     : diffLine.kind === "del" || diffLine.kind === "hunk" ? Style.dim
                                     : diffLine.kind === "meta" ? Style.faint : Style.text2
                                font.family: Style.mono
                                font.variableAxes: diffLine.kind === "head" ? Style.narrowMedium : Style.narrow
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
                visible: !(view.hasIntel && view.files.length > 0) && view.gateOutput === ""
                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(560, parent.width - 48)
                    spacing: 10
                    Crosshair { Layout.alignment: Qt.AlignHCenter }
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        horizontalAlignment: Text.AlignHCenter
                        text: view.hasIntel ? qsTr("No files changed this cycle") : qsTr("No intel for this cycle")
                        wrapMode: Text.Wrap
                        color: Style.text
                        font.family: Style.display
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                        font.letterSpacing: -0.3
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        visible: !view.hasIntel
                        text: qsTr("Fireteam snapshots cycles in git repositories. Run git init in the project to get diffs and rollback.")
                        wrapMode: Text.Wrap
                        color: Style.text2
                        font.family: Style.body
                        font.pixelSize: 13
                        lineHeight: 1.15
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 28
                Layout.rightMargin: 28
                Layout.topMargin: 14
                Layout.bottomMargin: 14
                spacing: 14
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
