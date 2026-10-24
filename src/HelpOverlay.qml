import QtQuick
import QtQuick.Layouts

// Every shortcut, shown with ?.
Item {
    id: help
    visible: false

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.8)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: help.visible = false }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(560, parent.width - 48)
        height: column.implicitHeight + 56
        color: Qt.rgba(0.04, 0.05, 0.065, 0.97)
        border.color: Style.line
        radius: theme.radius
        // Clicks on the panel itself mustn't reach the dismissing backdrop.
        MouseArea { anchors.fill: parent }
        Rectangle { width: parent.width; height: 3; color: theme.accent }

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: 28
            spacing: 10
            Text {
                text: qsTr("Controls")
                color: Style.text
                font.family: Style.display
                font.pixelSize: 28
                font.weight: Font.Black
                font.letterSpacing: 5
                font.capitalization: Font.AllUppercase
            }
            Repeater {
                model: [
                    ["N", qsTr("Plan a new operation")],
                    [qsTr("Space"), qsTr("Deploy, resume, or redeploy the selected operation")],
                    ["T", qsTr("Send orders to the selected operation")],
                    ["H", qsTr("Hold after the current cycle, or lift the hold")],
                    ["E", qsTr("Amend the briefing of an operation that isn't deployed")],
                    ["X", qsTr("Abort the selected operation")],
                    ["↑ ↓  J K", qsTr("Move through the roster")],
                    ["R", qsTr("Open the latest debrief")],
                    ["D", qsTr("Open the operation dossier")],
                    ["O", qsTr("Open the project directory")],
                    [qsTr("Del"), qsTr("Stand down (remove) the selected operation")],
                    ["Ctrl+Enter", qsTr("Deploy from the briefing")],
                    ["Esc", qsTr("Close a panel")],
                    ["?", qsTr("Show or hide these controls")],
                    ["Q", qsTr("Quit")]
                ]
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 16
                    Text {
                        Layout.preferredWidth: 110
                        text: modelData[0]
                        color: theme.accent
                        font.family: Style.mono
                        font.pixelSize: 13
                        font.bold: true
                    }
                    Text {
                        Layout.fillWidth: true
                        text: modelData[1]
                        wrapMode: Text.Wrap
                        color: Style.text
                        font.family: Style.display
                        font.pixelSize: 13
                    }
                }
            }
        }
    }
}
