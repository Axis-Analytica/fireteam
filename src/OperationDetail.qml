import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Everything about the selected operation: its orders, the live comms feed
// from the agent, the latest sitrep, the debriefs, and the changed files.
Item {
    id: detail
    property var op: null
    property int row: -1
    readonly property bool live: op !== null && op.status === "deployed"
    // Below this width the side column moves under the comms.
    readonly property bool compact: width < 760

    signal deployRequested()
    signal abortRequested()
    signal removeRequested()

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius

    // The codename glitches in whenever the selection changes.
    onOpChanged: if (op) intro.restart()
    SequentialAnimation {
        id: intro
        ParallelAnimation {
            NumberAnimation { target: title; property: "opacity"; from: 0; to: 1; duration: 260 }
            NumberAnimation { target: title; property: "x"; from: -24; to: 0; duration: 320; easing.type: Easing.OutCubic }
            NumberAnimation { target: ghost; property: "opacity"; from: 0.8; to: 0; duration: 420 }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 16
        visible: detail.op !== null

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
                text: detail.op ? qsTr("Operation // %1 · planned %2").arg(detail.op.opId)
                                      .arg(Qt.formatDateTime(detail.op.created, "d MMM HH:mm")) : ""
                color: Style.dim
                font.family: Style.mono
                font.pixelSize: 11
                font.letterSpacing: 2
                font.capitalization: Font.AllUppercase
            }
            Item {
                Layout.fillWidth: true
                implicitHeight: title.implicitHeight
                clip: true
                Text {
                    id: ghost
                    x: title.x + 4
                    text: title.text
                    color: theme.accent
                    opacity: 0
                    font: title.font
                }
                Text {
                    id: title
                    width: parent.width
                    text: detail.op ? detail.op.codename : ""
                    elide: Text.ElideRight
                    color: Style.text
                    font.family: Style.display
                    font.pixelSize: detail.compact ? 34 : 52
                    font.weight: Font.Black
                    font.letterSpacing: 6
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 8
            Chip {
                text: detail.op ? Style.statusLabel(detail.op.status) : ""
                tone: detail.op ? Style.statusColor(detail.op.status, theme.accent) : Style.dim
                solid: true
            }
            Chip {
                text: detail.op && detail.op.roe === "free" ? qsTr("ROE · weapons free") : qsTr("ROE · restricted")
                tone: detail.op && detail.op.roe === "free" ? Style.danger : Style.dim
            }
            Chip { text: detail.op && detail.op.model ? detail.op.model : qsTr("Default model"); tone: Style.dim }
            Chip {
                // claude reports what the run would cost at API prices; on a
                // subscription it counts against the plan's usage, not a bill.
                text: detail.op ? qsTr("≈ $%1 API value").arg(detail.op.cost.toLocaleString(Qt.locale(), 'f', 2)) : ""
                tone: Style.dim
            }
            Chip { text: detail.op ? detail.op.directory : ""; tone: Style.dim; mono: true }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            SectionLabel {
                Layout.fillWidth: true
                text: qsTr("Cycles")
                detail: detail.op ? qsTr("%1 of %2 complete").arg(detail.op.cyclesDone).arg(detail.op.cycles) : ""
            }
            CycleTrack {
                Layout.fillWidth: true
                cycles: detail.op ? detail.op.cycles : 1
                done: detail.op ? detail.op.cyclesDone : 0
                live: detail.live
            }
            SectionLabel {
                Layout.fillWidth: true
                Layout.topMargin: 6
                text: qsTr("Context")
                detail: !detail.op ? ""
                    : qsTr("%1 / %2 · session %3 · %4").arg(Style.tokens(detail.op.context))
                          .arg(Style.tokens(detail.op.contextWindow)).arg(detail.op.session)
                          .arg(detail.op.handoffAt > 0 ? qsTr("hand off at %1").arg(Style.tokens(detail.op.handoffAt))
                                                       : qsTr("no hand-off"))
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                ContextGauge {
                    Layout.fillWidth: true
                    used: detail.op ? detail.op.context : 0
                    window: detail.op ? detail.op.contextWindow : 1000000
                    line: detail.op ? detail.op.handoffAt : 0
                }
                Text {
                    visible: detail.op !== null && detail.op.handoffBrief.length > 0
                    text: qsTr("Handoff brief ↗")
                    color: theme.accent
                    font.family: Style.display
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    font.letterSpacing: 2
                    font.capitalization: Font.AllUppercase
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: ops.openReport(detail.op.handoffBrief) }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: detail.live
                text: "▸ " + (detail.op && detail.op.activity ? detail.op.activity : qsTr("Awaiting contact…"))
                elide: Text.ElideRight
                color: theme.accent
                font.family: Style.mono
                font.pixelSize: 12
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: detail.compact ? 1 : 2
            columnSpacing: 18
            rowSpacing: 12

            // Comms: the agent's stream, newest at the bottom.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                spacing: 8
                SectionLabel {
                    Layout.fillWidth: true
                    text: qsTr("Comms")
                    detail: detail.live ? qsTr("Live") : ""
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Qt.rgba(0, 0, 0, 0.45)
                    border.color: Style.line
                    radius: theme.radius
                    ListView {
                        id: comms
                        anchors.fill: parent
                        anchors.margins: 12
                        clip: true
                        spacing: 6
                        model: detail.op ? detail.op.comms : []
                        onCountChanged: Qt.callLater(positionViewAtEnd)
                        Component.onCompleted: positionViewAtEnd()
                        ScrollBar.vertical: ScrollBar {}
                        delegate: RowLayout {
                            id: line
                            required property var modelData
                            width: ListView.view.width - 10
                            spacing: 10
                            readonly property color tone: {
                                switch (modelData.kind) {
                                case "error": return Style.danger
                                case "tool": return theme.accent
                                case "result": return Style.good
                                case "sys": return Style.dim
                                }
                                return Style.text
                            }
                            Text {
                                Layout.alignment: Qt.AlignTop
                                text: line.modelData.time
                                color: Style.faint
                                font.family: Style.mono
                                font.pixelSize: 11
                            }
                            Text {
                                Layout.alignment: Qt.AlignTop
                                Layout.preferredWidth: 52
                                text: {
                                    switch (line.modelData.kind) {
                                    case "error": return qsTr("ERR")
                                    case "tool": return qsTr("ACT")
                                    case "result": return qsTr("SITREP")
                                    case "sys": return qsTr("HQ")
                                    }
                                    return qsTr("AGENT")
                                }
                                color: line.tone
                                font.family: Style.mono
                                font.pixelSize: 11
                                font.bold: true
                            }
                            Text {
                                Layout.fillWidth: true
                                text: line.modelData.text
                                wrapMode: Text.Wrap
                                maximumLineCount: line.modelData.kind === "say" ? 12 : 3
                                elide: Text.ElideRight
                                color: line.modelData.kind === "say" ? Style.text : line.tone
                                opacity: line.modelData.kind === "sys" ? 0.9 : 1
                                font.family: Style.mono
                                font.pixelSize: 12
                                textFormat: Text.PlainText
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: comms.count === 0
                        text: qsTr("Radio silence")
                        color: Style.faint
                        font.family: Style.display
                        font.pixelSize: 13
                        font.letterSpacing: 4
                        font.capitalization: Font.AllUppercase
                    }
                }
            }

            ColumnLayout {
                readonly property int sideWidth: detail.compact ? detail.width : Math.round(Math.min(380, detail.width * 0.36))
                Layout.preferredWidth: sideWidth
                Layout.maximumWidth: sideWidth
                Layout.fillWidth: detail.compact
                Layout.fillHeight: !detail.compact
                Layout.maximumHeight: detail.compact ? 260 : Infinity
                spacing: 8

                SectionLabel { Layout.fillWidth: true; text: qsTr("Objective") }
                Text {
                    id: objectiveText
                    Layout.fillWidth: true
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    text: detail.op ? detail.op.objective : ""
                    wrapMode: Text.Wrap
                    color: Style.text
                    font.family: Style.display
                    font.pixelSize: 13
                    lineHeight: 1.25
                    textFormat: Text.PlainText
                }

                SectionLabel { Layout.fillWidth: true; Layout.topMargin: 8; text: qsTr("Sitrep") }
                Text {
                    id: sitrepText
                    Layout.fillWidth: true
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    text: detail.op && detail.op.sitrep ? detail.op.sitrep : qsTr("No sitrep yet.")
                    wrapMode: Text.Wrap
                    color: detail.op && detail.op.sitrep ? Style.text : Style.faint
                    font.family: Style.display
                    font.pixelSize: 13
                    lineHeight: 1.25
                    textFormat: Text.PlainText
                }

                SectionLabel {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    text: qsTr("Debriefs")
                    detail: detail.op ? "" + detail.op.reports.length : ""
                }
                ListView {
                    id: debriefs
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, 150)
                    clip: true
                    interactive: contentHeight > height
                    model: detail.op ? detail.op.reports.slice().reverse() : []
                    delegate: Item {
                        id: debrief
                        required property string modelData
                        required property int index
                        width: ListView.view.width
                        height: 30
                        Rectangle {
                            anchors.fill: parent
                            color: debriefHover.hovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                            radius: Math.min(4, theme.radius)
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            Text {
                                text: "▤"
                                color: theme.accent
                                font.pixelSize: 13
                            }
                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Cycle %1 debrief").arg(Style.pad(detail.op.reports.length - debrief.index))
                                color: Style.text
                                font.family: Style.display
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                font.letterSpacing: 2
                                font.capitalization: Font.AllUppercase
                            }
                            Text { text: "↗"; color: Style.dim; font.pixelSize: 13 }
                        }
                        HoverHandler { id: debriefHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: ops.openReport(debrief.modelData) }
                    }
                }
                Text {
                    visible: debriefs.count === 0
                    text: qsTr("Debriefs land here as each cycle completes.")
                    color: Style.faint
                    font.family: Style.display
                    font.pixelSize: 12
                }

                SectionLabel {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    text: qsTr("Intel")
                    detail: detail.op && detail.op.intel.length ? qsTr("%1 changed").arg(detail.op.intel.length) : ""
                }
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 0
                    clip: true
                    model: detail.op ? detail.op.intel : []
                    ScrollBar.vertical: ScrollBar {}
                    delegate: Text {
                        required property string modelData
                        width: ListView.view.width - 10
                        text: modelData
                        elide: Text.ElideMiddle
                        color: modelData.startsWith("??") ? Style.good : modelData.startsWith(" D") || modelData.startsWith("D") ? Style.danger : Style.dim
                        font.family: Style.mono
                        font.pixelSize: 11
                    }
                    Text {
                        visible: parent.count === 0
                        text: qsTr("No changed files reported by git.")
                        color: Style.faint
                        font.family: Style.display
                        font.pixelSize: 12
                    }
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            Layout.preferredHeight: childrenRect.height
            spacing: 10
            TacticalButton {
                text: detail.op && detail.op.cyclesDone >= detail.op.cycles ? qsTr("Redeploy +1") : detail.op && detail.op.cyclesDone > 0 ? qsTr("Resume") : qsTr("Deploy")
                key: qsTr("Space")
                primary: true
                enabled: detail.op && !detail.live
                onClicked: detail.deployRequested()
            }
            TacticalButton {
                text: qsTr("Abort")
                key: "X"
                danger: true
                enabled: detail.live
                onClicked: detail.abortRequested()
            }
            TacticalButton {
                text: qsTr("Dossier")
                key: "D"
                enabled: detail.op && detail.op.dossier.length > 0
                onClicked: ops.openDossier(detail.row)
            }
            TacticalButton {
                text: qsTr("Project")
                key: "O"
                enabled: detail.op !== null
                onClicked: ops.openProject(detail.row)
            }
            TacticalButton {
                text: qsTr("Stand down")
                key: qsTr("Del")
                danger: true
                enabled: detail.op && !detail.live
                onClicked: detail.removeRequested()
            }
        }
    }

    // Nothing selected: point at the one thing to do.
    ColumnLayout {
        anchors.centerIn: parent
        visible: detail.op === null
        spacing: 14
        Crosshair { Layout.alignment: Qt.AlignHCenter }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("No operations on the board")
            color: Style.text
            font.family: Style.display
            font.pixelSize: 26
            font.weight: Font.Black
            font.letterSpacing: 5
            font.capitalization: Font.AllUppercase
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Plan one and send a fireteam of Claude Code agents in.")
            color: Style.dim
            font.family: Style.display
            font.pixelSize: 14
        }
        KeyHint { Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 8; key: "N"; label: qsTr("Plan operation") }
    }
}
