import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Every shortcut, shown with ?.
Item {
    id: help
    visible: false

    onVisibleChanged: if (visible) { enter.restart(); list.contentY = 0 }

    readonly property var controls: [
        ["Ctrl+K", qsTr("Command palette: any action or operation, or type a request to deploy it")],
        ["I", qsTr("Inbox: everything waiting on you, across every operation")],
        ["N", qsTr("Plan a new operation")],
        [qsTr("Space"), qsTr("Deploy, resume, or redeploy the selected operation")],
        ["T", qsTr("Send orders to the selected operation")],
        ["H", qsTr("Hold after the current cycle, or lift the hold")],
        ["A", qsTr("Respond to an agent waiting on you, or review refused commands")],
        ["E", qsTr("Amend the briefing of an operation that isn't deployed")],
        ["X", qsTr("Abort the selected operation")],
        ["↑ ↓  J K", qsTr("Move through the roster")],
        ["V", qsTr("Intel: what the latest cycle changed, file by file")],
        ["[ ]  J K", qsTr("In intel: previous or next cycle, and file")],
        ["/", qsTr("Search the comms")],
        ["P", qsTr("Field terminal: steer operations from your phone")],
        ["F", qsTr("Field manual: what operations learned about this project")],
        ["Shift+R", qsTr("Replay the selected operation from its comms")],
        ["Ctrl+F", qsTr("Search every operation, archive included")],
        ["G", qsTr("Knowledge graph: map the project's code, and what operations changed")],
        ["C", qsTr("Campaigns: plan a large objective as several operations")],
        ["S", qsTr("Service record: totals across every operation")],
        ["M", qsTr("Switch between the board and the theatre map")],
        ["Shift+M", qsTr("Turn interface sounds on or off")],
        ["R", qsTr("Open the latest debrief")],
        ["D", qsTr("Open the operation dossier")],
        ["O", qsTr("Open the project directory")],
        [qsTr("Del"), qsTr("Stand down (remove) the selected operation")],
        ["Ctrl+Z", qsTr("Undo standing down, for a few seconds after")],
        ["Ctrl+Enter", qsTr("Deploy from the briefing")],
        [",", qsTr("Options and About")],
        ["Esc", qsTr("Close a panel")],
        ["?", qsTr("Show or hide these controls")],
        ["X", qsTr("On a staged or pinned operation: take it out of the queue")],
        ["Q", qsTr("Quit")]
    ]

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Style.bg.r, Style.bg.g, Style.bg.b, 0.86)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: help.visible = false }
    }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(980, parent.width - 48)
        height: Math.min(header.height + 1 + grid.implicitHeight + 32, parent.height - 48)
        color: Style.panel
        border.color: Style.lineStrong
        radius: theme.radius
        transform: Translate { id: lift }
        // Clicks on the panel itself mustn't reach the dismissing backdrop.
        MouseArea { anchors.fill: parent }
        Brackets { anchors.fill: parent; anchors.margins: -1; size: 12 }

        ParallelAnimation {
            id: enter
            NumberAnimation { target: sheet; property: "opacity"; from: 0; to: 1; duration: 140 }
            NumberAnimation { target: lift; property: "y"; from: 8; to: 0; duration: 180; easing.type: Easing.OutCubic }
        }

        // Header: a comment for an eyebrow, the title, and how to close it.
        Item {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            height: 96
            ColumnLayout {
                anchors.left: parent.left
                anchors.leftMargin: 28
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 20
                spacing: 4
                Text {
                    text: "# " + help.controls.length + " · ?"
                    color: Style.dim
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 11
                }
                Text {
                    text: qsTr("Controls")
                    color: Style.text
                    font.family: Style.display
                    font.pixelSize: 28
                    font.weight: Font.DemiBold
                    font.letterSpacing: -0.6
                }
            }
            KeyHint {
                anchors.right: parent.right
                anchors.rightMargin: 28
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 24
                key: "Esc"
                label: qsTr("Close a panel")
            }
        }
        Rectangle { id: rule; anchors.top: header.bottom; width: parent.width; height: 1; color: Style.line }

        Flickable {
            id: list
            anchors.top: rule.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 28
            anchors.rightMargin: 28
            anchors.topMargin: 12
            anchors.bottomMargin: 20
            contentHeight: grid.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollIndicator.vertical: ScrollIndicator { parent: list.parent; anchors.top: list.top; anchors.bottom: list.bottom; anchors.right: parent.right; anchors.rightMargin: 6 }

            // Two columns read top to bottom when there's room, one otherwise.
            GridLayout {
                id: grid
                width: list.width
                flow: GridLayout.TopToBottom
                readonly property int columnCount: list.width >= 760 ? 2 : 1
                rows: Math.ceil(help.controls.length / columnCount)
                columnSpacing: 40
                rowSpacing: 0
                Repeater {
                    model: help.controls
                    delegate: Item {
                        id: entry
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: Math.max(34, description.implicitHeight + 16)
                        RowLayout {
                            anchors.fill: parent
                            spacing: 14
                            // Each key as a small moulded cap; "↑ ↓  J K" is two.
                            Row {
                                Layout.preferredWidth: 88
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 4
                                Repeater {
                                    model: entry.modelData[0].split("  ")
                                    delegate: Rectangle {
                                        required property string modelData
                                        width: Math.max(20, cap.implicitWidth + 10)
                                        height: 20
                                        color: Style.bg
                                        border.color: Style.lineStrong
                                        radius: Math.min(3, theme.radius)
                                        Text {
                                            id: cap
                                            anchors.centerIn: parent
                                            text: parent.modelData
                                            color: Style.text
                                            font.family: Style.mono
                                            font.variableAxes: Style.narrow
                                            font.pixelSize: 10
                                        }
                                    }
                                }
                            }
                            Text {
                                id: description
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                text: entry.modelData[1]
                                wrapMode: Text.Wrap
                                color: Style.text2
                                font.family: Style.body
                                font.pixelSize: 13
                            }
                        }
                        // A hairline between rows, not under the last in a column.
                        Rectangle {
                            visible: (entry.index + 1) % grid.rows !== 0 && entry.index < help.controls.length - 1
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 1
                            color: Style.line
                        }
                    }
                }
            }
        }
    }
}
