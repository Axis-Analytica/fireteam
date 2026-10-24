import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Search across everything operations wrote: objectives, debriefs, hand-off
// briefs, reviews, and every comms log, archived operations included.
Item {
    id: panel
    visible: false
    property var results: []
    signal picked(int row, string path)

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius

    function open() {
        visible = true
        enter.restart()
        query.forceActiveFocus()
        query.selectAll()
    }
    function close() { visible = false }

    Timer { id: debounce; interval: 250; onTriggered: panel.results = ops.search(query.text) }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.8)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: panel.close() }
    }

    Rectangle {
        id: sheet
        anchors.horizontalCenter: parent.horizontalCenter
        y: 60
        width: Math.min(900, parent.width - 48)
        height: Math.min(column.implicitHeight + 48, parent.height - 120)
        color: Qt.rgba(0.04, 0.05, 0.065, 0.98)
        border.color: Style.line
        radius: theme.radius
        // Clicks on the panel itself mustn't reach the dismissing backdrop.
        MouseArea { anchors.fill: parent }
        Rectangle { width: parent.width; height: 3; color: theme.accent }

        ParallelAnimation {
            id: enter
            NumberAnimation { target: sheet; property: "opacity"; from: 0; to: 1; duration: 140 }
        }

        ColumnLayout {
            id: column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 24
            spacing: 12
            TextField {
                id: query
                Layout.fillWidth: true
                placeholderText: qsTr("Search every operation: objectives, debriefs, briefs, reviews, comms")
                font.family: Style.display
                font.pixelSize: 16
                onTextChanged: debounce.restart()
                Keys.onDownPressed: list.forceActiveFocus()
                onAccepted: if (panel.results.length > 0) panel.picked(panel.results[0].row, panel.results[0].path)
            }
            Text {
                visible: query.text.trim().length >= 2 && panel.results.length === 0 && !debounce.running
                text: qsTr("Nothing found")
                color: Style.faint
                font.family: Style.display
                font.pixelSize: 13
                font.letterSpacing: 3 * Style.tracking
                font.capitalization: Font.AllUppercase
            }
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, sheet.parent ? sheet.parent.height - 260 : 400)
                clip: true
                spacing: 4
                model: panel.results
                keyNavigationEnabled: true
                ScrollBar.vertical: ScrollBar {}
                delegate: Rectangle {
                    id: result
                    required property var modelData
                    required property int index
                    width: ListView.view.width - 10
                    height: resultColumn.implicitHeight + 16
                    color: resultHover.hovered || ListView.isCurrentItem ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                    radius: Math.min(4, theme.radius)
                    ColumnLayout {
                        id: resultColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 2
                        RowLayout {
                            spacing: 10
                            Text {
                                text: result.modelData.codename
                                color: Style.text
                                font.family: Style.display
                                font.pixelSize: 13
                                font.weight: Font.Black
                                font.letterSpacing: 2 * Style.tracking
                            }
                            Text {
                                text: result.modelData.kind.toUpperCase() + (result.modelData.archived ? qsTr(" · archived") : "")
                                color: theme.accent
                                font.family: Style.mono
                                font.pixelSize: 10
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: result.modelData.snippet
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            color: Style.dim
                            font.family: Style.mono
                            font.pixelSize: 11
                            textFormat: Text.PlainText
                        }
                    }
                    HoverHandler { id: resultHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: panel.picked(result.modelData.row, result.modelData.path) }
                    Keys.onReturnPressed: panel.picked(result.modelData.row, result.modelData.path)
                }
            }
        }
    }
}
