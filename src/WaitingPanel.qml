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
        color: Qt.rgba(0, 0, 0, 0.8)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: panel.close() }
    }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(820, parent.width - 48)
        height: Math.min(column.implicitHeight + 64, parent.height - 48)
        color: Qt.rgba(0.04, 0.05, 0.065, 0.97)
        border.color: Style.line
        radius: theme.radius
        // Clicks on the panel itself mustn't reach the dismissing backdrop.
        MouseArea { anchors.fill: parent }
        Rectangle { width: parent.width; height: 3; color: Style.danger }

        ParallelAnimation {
            id: enter
            NumberAnimation { target: sheet; property: "opacity"; from: 0; to: 1; duration: 160 }
            NumberAnimation { target: sheet; property: "scale"; from: 0.97; to: 1; duration: 220; easing.type: Easing.OutCubic }
        }

        ScrollView {
            anchors.fill: parent
            anchors.margins: 32
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                id: column
                width: parent.width
                spacing: 14

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: panel.op ? qsTr("Field link // %1").arg(panel.op.codename) : ""
                        color: Style.danger
                        font.family: Style.mono
                        font.pixelSize: 11
                        font.letterSpacing: 4 * Style.tracking
                        font.capitalization: Font.AllUppercase
                    }
                    Text {
                        text: qsTr("Waiting on you")
                        color: Style.text
                        font.family: Style.display
                        font.pixelSize: 30
                        font.weight: Font.Black
                        font.letterSpacing: 5 * Style.tracking
                        font.capitalization: Font.AllUppercase
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        text: qsTr("The agent has stopped mid-cycle for these. Questions without an answer in 30 minutes are left to its judgement; permission without an answer in 20 minutes is refused.")
                        wrapMode: Text.Wrap
                        color: Style.dim
                        font.family: Style.display
                        font.pixelSize: 13
                    }
                }

                // Questions: an option is one click; anything else is typed.
                Repeater {
                    model: panel.op ? panel.op.questions : []
                    delegate: Rectangle {
                        id: question
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: questionColumn.implicitHeight + 28
                        color: Qt.rgba(1, 1, 1, 0.03)
                        border.color: Style.line
                        radius: Math.min(4, theme.radius)
                        Rectangle { width: 3; height: parent.height; color: Style.amber }
                        ColumnLayout {
                            id: questionColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 14
                            anchors.leftMargin: 20
                            spacing: 10
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: qsTr("Question")
                                    color: Style.amber
                                    font.family: Style.display
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    font.letterSpacing: 3 * Style.tracking
                                    font.capitalization: Font.AllUppercase
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: question.modelData.time
                                    color: Style.faint
                                    font.family: Style.mono
                                    font.pixelSize: 11
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: question.modelData.question
                                wrapMode: Text.Wrap
                                color: Style.text
                                font.family: Style.display
                                font.pixelSize: 15
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
                                    font.family: Style.display
                                    font.pixelSize: 13
                                    onAccepted: if (text.trim().length > 0) ops.answer(panel.row, question.modelData.id, text)
                                }
                                TacticalButton {
                                    text: qsTr("Send")
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
                        implicitHeight: promptColumn.implicitHeight + 28
                        color: Qt.rgba(1, 1, 1, 0.03)
                        border.color: Style.line
                        radius: Math.min(4, theme.radius)
                        Rectangle { width: 3; height: parent.height; color: Style.danger }
                        ColumnLayout {
                            id: promptColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 14
                            anchors.leftMargin: 20
                            spacing: 10
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: qsTr("Permission")
                                    color: Style.danger
                                    font.family: Style.display
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    font.letterSpacing: 3 * Style.tracking
                                    font.capitalization: Font.AllUppercase
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: prompt.modelData.time
                                    color: Style.faint
                                    font.family: Style.mono
                                    font.pixelSize: 11
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: prompt.modelData.summary
                                wrapMode: Text.WrapAnywhere
                                maximumLineCount: 4
                                elide: Text.ElideRight
                                color: Style.text
                                font.family: Style.mono
                                font.pixelSize: 13
                                textFormat: Text.PlainText
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
                                        width: ruleText.implicitWidth + 20
                                        height: 26
                                        color: prompt.chosen === index ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.16) : "transparent"
                                        border.color: prompt.chosen === index ? theme.accent : Style.line
                                        radius: Math.min(4, theme.radius)
                                        Text {
                                            id: ruleText
                                            anchors.centerIn: parent
                                            text: (ruleChip.index === 0 ? qsTr("Always any  ") : qsTr("Always only  ")) + ruleChip.modelData.join("  +  ")
                                            color: prompt.chosen === ruleChip.index ? Style.text : Style.dim
                                            font.family: Style.mono
                                            font.pixelSize: 11
                                        }
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
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

                RowLayout {
                    Layout.fillWidth: true
                    TacticalButton { text: qsTr("Later"); key: "Esc"; onClicked: panel.close() }
                    Item { Layout.fillWidth: true }
                }
            }
        }
    }
}
