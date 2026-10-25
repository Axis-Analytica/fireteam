import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// An agent waiting on the operator, mid-cycle: its questions, with the
// options it offered, and the commands it needs permission for.
Item {
    id: panel
    visible: false
    property var op: null
    property int row: -1
    // Which suggested rule "Always" remembers, per prompt id.
    property var choices: ({})
    readonly property int waiting: op ? op.questions.length + op.prompts.length : 0

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius

    function open(target, targetRow) {
        op = target
        row = targetRow
        choices = ({})
        visible = true
        enter.restart()
    }
    function close() { visible = false }
    // Nothing left to answer: back to the board.
    onWaitingChanged: if (visible && waiting === 0) close()

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Style.bg.r, Style.bg.g, Style.bg.b, 0.86)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: panel.close() }
    }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(820, parent.width - 48)
        height: Math.min(head.implicitHeight + column.implicitHeight + foot.implicitHeight + 2 + 28 + 20 + 40 + 32,
                         parent.height - 48)
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

            // Who is waiting, and the rules of the wait.
            ColumnLayout {
                id: head
                Layout.fillWidth: true
                Layout.margins: 32
                Layout.topMargin: 28
                Layout.bottomMargin: 20
                spacing: 4
                Text {
                    Layout.fillWidth: true
                    text: panel.op ? "# " + qsTr("Field link // %1").arg(panel.op.codename) : ""
                    elide: Text.ElideRight
                    color: Style.dim
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 11
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.topMargin: 2
                        implicitWidth: 8; implicitHeight: 8
                        color: Style.amber
                    }
                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Waiting on you")
                        elide: Text.ElideRight
                        color: Style.text
                        font.family: Style.display
                        font.pixelSize: 28
                        font.weight: Font.DemiBold
                        font.letterSpacing: -0.6
                    }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: Style.pad(panel.waiting)
                        color: Style.text2
                        font.family: Style.mono
                        font.variableAxes: Style.figure
                        font.pixelSize: 22
                        font.features: { "tnum": 1 }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    text: qsTr("The agent has stopped mid-cycle for these. Questions without an answer in 30 minutes are left to its judgement; permission without an answer in 20 minutes is refused.")
                    wrapMode: Text.Wrap
                    color: Style.text2
                    font.family: Style.body
                    font.pixelSize: 13
                    lineHeight: 1.15
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }

            ScrollView {
                id: scroller
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 32
                Layout.rightMargin: 32
                Layout.topMargin: 20
                Layout.bottomMargin: 20
                contentWidth: availableWidth
                clip: true

                ColumnLayout {
                    id: column
                    width: scroller.availableWidth
                    spacing: 12

                    // Questions: an option is one click; anything else is typed.
                    Repeater {
                        model: panel.op ? panel.op.questions : []
                        delegate: Rectangle {
                            id: question
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: questionColumn.implicitHeight + 32
                            color: Style.bg
                            border.color: Style.line
                            radius: Math.min(2, theme.radius)
                            ColumnLayout {
                                id: questionColumn
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 16
                                spacing: 12
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Rectangle { implicitWidth: 6; implicitHeight: 6; color: Style.amber; Layout.alignment: Qt.AlignVCenter }
                                    Text {
                                        text: qsTr("Question")
                                        color: Style.text2
                                        font.family: Style.body
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: question.modelData.time
                                        color: Style.dim
                                        font.family: Style.mono
                                        font.variableAxes: Style.narrow
                                        font.pixelSize: 11
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: question.modelData.question
                                    wrapMode: Text.Wrap
                                    color: Style.text
                                    font.family: Style.body
                                    font.pixelSize: 15
                                    font.weight: Font.Medium
                                    lineHeight: 1.15
                                    textFormat: Text.PlainText
                                }
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    visible: question.modelData.options.length > 0
                                    Repeater {
                                        model: question.modelData.options
                                        delegate: TacticalButton {
                                            required property string modelData
                                            required property int index
                                            text: modelData
                                            primary: index === 0
                                            onClicked: ops.answer(panel.row, question.modelData.id, modelData)
                                        }
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    TextField {
                                        id: reply
                                        Layout.fillWidth: true
                                        placeholderText: question.modelData.options.length > 0 ? qsTr("Or answer in your own words") : qsTr("Your answer")
                                        font.family: Style.body
                                        font.pixelSize: 13
                                        onAccepted: if (text.trim().length > 0) ops.answer(panel.row, question.modelData.id, text)
                                    }
                                    TacticalButton {
                                        text: qsTr("Send")
                                        key: "↵"
                                        enabled: reply.text.trim().length > 0
                                        onClicked: ops.answer(panel.row, question.modelData.id, reply.text)
                                    }
                                }
                            }
                        }
                    }

                    // Permission: once, always for this operation, or no.
                    Repeater {
                        model: panel.op ? panel.op.prompts : []
                        delegate: Rectangle {
                            id: prompt
                            required property var modelData
                            readonly property int chosen: panel.choices[modelData.id] === undefined ? 0 : panel.choices[modelData.id]
                            Layout.fillWidth: true
                            implicitHeight: promptColumn.implicitHeight + 32
                            color: Style.bg
                            border.color: Style.line
                            radius: Math.min(2, theme.radius)
                            ColumnLayout {
                                id: promptColumn
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 16
                                spacing: 12
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Rectangle { implicitWidth: 6; implicitHeight: 6; color: Style.danger; Layout.alignment: Qt.AlignVCenter }
                                    Text {
                                        text: qsTr("Permission")
                                        color: Style.text2
                                        font.family: Style.body
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: prompt.modelData.time
                                        color: Style.dim
                                        font.family: Style.mono
                                        font.variableAxes: Style.narrow
                                        font.pixelSize: 11
                                    }
                                }
                                // The command, as a prompt line in a well.
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: commandText.implicitHeight + 20
                                    color: Style.panel
                                    border.color: Style.line
                                    radius: Math.min(2, theme.radius)
                                    Text {
                                        id: commandPrompt
                                        x: 12; y: 10
                                        text: "$"
                                        color: theme.accent
                                        font.family: Style.mono
                                        font.variableAxes: Style.narrow
                                        font.pixelSize: 13
                                    }
                                    Text {
                                        id: commandText
                                        anchors.left: commandPrompt.right
                                        anchors.leftMargin: 10
                                        anchors.right: parent.right
                                        anchors.rightMargin: 12
                                        y: 10
                                        text: prompt.modelData.summary
                                        wrapMode: Text.WrapAnywhere
                                        maximumLineCount: 4
                                        elide: Text.ElideRight
                                        color: Style.text
                                        font.family: Style.mono
                                        font.variableAxes: Style.narrow
                                        font.pixelSize: 13
                                        textFormat: Text.PlainText
                                    }
                                }
                                // What "Always" remembers, when there's a choice.
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    visible: prompt.modelData.choices.length > 1
                                    Repeater {
                                        model: prompt.modelData.choices
                                        delegate: Rectangle {
                                            id: ruleChip
                                            required property var modelData
                                            required property int index
                                            readonly property bool picked: prompt.chosen === index
                                            width: Math.min(ruleText.implicitWidth + 24, promptColumn.width)
                                            height: 28
                                            color: picked ? Style.wash : ruleHover.hovered ? Style.raised : Style.panel
                                            border.color: picked ? theme.accent : Style.line
                                            radius: Math.min(2, theme.radius)
                                            Text {
                                                id: ruleText
                                                anchors.verticalCenter: parent.verticalCenter
                                                x: 12
                                                width: parent.width - 24
                                                text: (ruleChip.index === 0 ? qsTr("Always any  ") : qsTr("Always only  ")) + ruleChip.modelData.join("  +  ")
                                                elide: Text.ElideRight
                                                color: ruleChip.picked ? Style.text : Style.dim
                                                font.family: Style.mono
                                                font.variableAxes: Style.narrow
                                                font.pixelSize: 11
                                            }
                                            HoverHandler { id: ruleHover; cursorShape: Qt.PointingHandCursor }
                                            TapHandler {
                                                onTapped: {
                                                    const next = Object.assign({}, panel.choices)
                                                    next[prompt.modelData.id] = ruleChip.index
                                                    panel.choices = next
                                                }
                                            }
                                        }
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    TacticalButton {
                                        text: qsTr("Deny")
                                        danger: true
                                        onClicked: ops.decide(panel.row, prompt.modelData.id, "deny")
                                    }
                                    Item { Layout.fillWidth: true }
                                    TacticalButton {
                                        text: qsTr("Always")
                                        onClicked: ops.decide(panel.row, prompt.modelData.id, "always", prompt.chosen)
                                    }
                                    TacticalButton {
                                        text: qsTr("Approve once")
                                        primary: true
                                        onClicked: ops.decide(panel.row, prompt.modelData.id, "once")
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }

            RowLayout {
                id: foot
                Layout.fillWidth: true
                Layout.leftMargin: 32
                Layout.rightMargin: 32
                Layout.topMargin: 16
                Layout.bottomMargin: 16
                spacing: 10
                TacticalButton { text: qsTr("Later"); key: "Esc"; onClicked: panel.close() }
                Item { Layout.fillWidth: true }
            }
        }
    }
}
