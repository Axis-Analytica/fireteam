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
        color: Qt.rgba(0, 0, 0, 0.78)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: radio.close() }
    }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(640, parent.width - 48)
        height: Math.min(column.implicitHeight + 64, parent.height - 48)
        color: Qt.rgba(0.04, 0.05, 0.065, 0.97)
        border.color: Style.line
        radius: theme.radius
        // Clicks on the panel itself mustn't reach the dismissing backdrop.
        MouseArea { anchors.fill: parent }
        Rectangle { width: parent.width; height: 3; color: Style.amber }

        ParallelAnimation {
            id: enter
            NumberAnimation { target: sheet; property: "opacity"; from: 0; to: 1; duration: 160 }
            NumberAnimation { target: sheet; property: "scale"; from: 0.97; to: 1; duration: 220; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: 32
            spacing: 14

            ColumnLayout {
                spacing: 2
                Text {
                    text: radio.op ? qsTr("Radio // %1").arg(radio.op.codename) : ""
                    color: Style.amber
                    font.family: Style.mono
                    font.pixelSize: 11
                    font.letterSpacing: 4 * Style.tracking
                    font.capitalization: Font.AllUppercase
                }
                Text {
                    text: qsTr("Send orders")
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
                    text: radio.live
                          ? qsTr("The agent is mid-cycle. These orders go out at the start of its next cycle and take priority over its plan.")
                          : qsTr("Transmit sends the agent back in for a cycle that starts with these orders. Queue keeps them for the next deploy.")
                    wrapMode: Text.Wrap
                    color: Style.dim
                    font.family: Style.display
                    font.pixelSize: 13
                }
            }

            // Orders already waiting, so nothing is sent twice by accident.
            ColumnLayout {
                Layout.fillWidth: true
                visible: radio.op !== null && radio.op.orders.length > 0
                spacing: 4
                SectionLabel {
                    Layout.fillWidth: true
                    text: qsTr("Queued")
                    detail: radio.op ? "" + radio.op.orders.length : ""
                }
                Repeater {
                    model: radio.op ? radio.op.orders : []
                    delegate: Text {
                        required property string modelData
                        Layout.fillWidth: true
                        text: "▸ " + modelData
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        color: Style.amber
                        font.family: Style.mono
                        font.pixelSize: 12
                        textFormat: Text.PlainText
                    }
                }
                Text {
                    text: qsTr("Withdraw queued orders")
                    color: Style.dim
                    font.family: Style.display
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    font.letterSpacing: 2 * Style.tracking
                    font.capitalization: Font.AllUppercase
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: ops.clearOrders(radio.row) }
                }
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 130
                TextArea {
                    id: message
                    placeholderText: qsTr("e.g. Use SQLite instead of JSON files, and add a test for the parser.")
                    wrapMode: TextArea.Wrap
                    font.family: Style.display
                    font.pixelSize: 14
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
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
