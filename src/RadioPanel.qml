import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Orders from command to one operation. A deployed agent gets them at the
// start of its next cycle; an idle one can be sent straight back in with them.
Item {
    id: radio
    visible: false
    property var op: null
    property int row: -1
    readonly property bool live: op !== null && op.status === "deployed"

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius

    function open(target, targetRow) {
        op = target
        row = targetRow
        message.text = ""
        visible = true
        enter.restart()
        message.forceActiveFocus()
    }
    function close() { visible = false }
    function transmit(deployNow) {
        if (message.text.trim().length === 0)
            return
        ops.sendOrders(row, message.text, deployNow && !live)
        visible = false
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Style.bg.r, Style.bg.g, Style.bg.b, 0.86)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: radio.close() }
    }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(640, parent.width - 48)
        height: Math.min(column.implicitHeight, parent.height - 48)
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
            id: column
            anchors.fill: parent
            spacing: 0

            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: 32
                Layout.topMargin: 28
                Layout.bottomMargin: 20
                spacing: 4
                Text {
                    Layout.fillWidth: true
                    text: radio.op ? "# " + qsTr("Radio // %1").arg(radio.op.codename) : ""
                    elide: Text.ElideRight
                    color: Style.dim
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 11
                }
                Text {
                    Layout.fillWidth: true
                    text: qsTr("Send orders")
                    elide: Text.ElideRight
                    color: Style.text
                    font.family: Style.display
                    font.pixelSize: 28
                    font.weight: Font.DemiBold
                    font.letterSpacing: -0.6
                }
                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    text: radio.live
                          ? qsTr("The agent is mid-cycle. These orders go out at the start of its next cycle and take priority over its plan.")
                          : qsTr("Transmit sends the agent back in for a cycle that starts with these orders. Queue keeps them for the next deploy.")
                    wrapMode: Text.Wrap
                    color: Style.text2
                    font.family: Style.body
                    font.pixelSize: 13
                    lineHeight: 1.15
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 32
                Layout.topMargin: 20
                Layout.bottomMargin: 20
                spacing: 16

                // Orders already waiting, so nothing is sent twice by accident.
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: radio.op !== null && radio.op.orders.length > 0
                    spacing: 6
                    SectionLabel {
                        Layout.fillWidth: true
                        text: qsTr("Queued")
                        detail: radio.op ? "" + radio.op.orders.length : ""
                    }
                    Repeater {
                        model: radio.op ? radio.op.orders : []
                        delegate: RowLayout {
                            required property string modelData
                            required property int index
                            Layout.fillWidth: true
                            spacing: 10
                            Text {
                                Layout.alignment: Qt.AlignTop
                                text: Style.pad(index + 1)
                                color: Style.faint
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 11
                                topPadding: 1
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                color: Style.text2
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 12
                                textFormat: Text.PlainText
                            }
                        }
                    }
                    Text {
                        Layout.topMargin: 2
                        text: qsTr("Withdraw queued orders")
                        color: withdrawHover.hovered ? Style.danger : Style.dim
                        font.family: Style.body
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        font.underline: withdrawHover.hovered
                        HoverHandler { id: withdrawHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: ops.clearOrders(radio.row) }
                    }
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 140
                    Layout.fillHeight: true
                    TextArea {
                        id: message
                        placeholderText: qsTr("e.g. Use SQLite instead of JSON files, and add a test for the parser.")
                        wrapMode: TextArea.Wrap
                        font.family: Style.body
                        font.pixelSize: 14
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 32
                Layout.rightMargin: 32
                Layout.topMargin: 16
                Layout.bottomMargin: 16
                spacing: 10
                TacticalButton { text: qsTr("Cancel"); key: "Esc"; onClicked: radio.close() }
                Item { Layout.fillWidth: true }
                TacticalButton {
                    visible: !radio.live
                    text: qsTr("Queue")
                    enabled: message.text.trim().length > 0
                    onClicked: radio.transmit(false)
                }
                TacticalButton {
                    text: radio.live ? qsTr("Queue for next cycle") : qsTr("Transmit")
                    key: "Ctrl+Enter"
                    primary: true
                    enabled: message.text.trim().length > 0
                    onClicked: radio.transmit(true)
                }
            }
        }
    }

    Shortcut {
        enabled: radio.visible
        sequences: ["Ctrl+Return", "Ctrl+Enter"]
        context: Qt.ApplicationShortcut
        onActivated: radio.transmit(true)
    }
}
