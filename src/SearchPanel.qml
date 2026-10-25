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
        color: Qt.rgba(Style.bg.r, Style.bg.g, Style.bg.b, 0.86)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: panel.close() }
    }

    Rectangle {
        id: sheet
        anchors.horizontalCenter: parent.horizontalCenter
        y: 60
        width: Math.min(900, parent.width - 48)
        height: Math.min(column.implicitHeight + 40, parent.height - 120)
        color: Style.panel
        border.color: Style.lineStrong
        radius: theme.radius
        // Clicks on the panel itself mustn't reach the dismissing backdrop.
        MouseArea { anchors.fill: parent }
        Brackets { anchors.fill: parent; anchors.margins: -1; size: 12 }

        ParallelAnimation {
            id: enter
            NumberAnimation { target: sheet; property: "opacity"; from: 0; to: 1; duration: 140 }
        }

        ColumnLayout {
            id: column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 20
            spacing: 12
            TextField {
                id: query
                Layout.fillWidth: true
                placeholderText: qsTr("Search every operation: objectives, debriefs, briefs, reviews, comms")
                Material.background: Style.bg
                font.family: Style.body
                font.pixelSize: 16
                onTextChanged: debounce.restart()
                Keys.onDownPressed: list.forceActiveFocus()
                onAccepted: if (panel.results.length > 0) panel.picked(panel.results[0].row, panel.results[0].path)
            }
            Text {
                visible: query.text.trim().length >= 2 && panel.results.length === 0 && !debounce.running
                Layout.leftMargin: 2
                Layout.bottomMargin: 4
                text: qsTr("Nothing found")
                color: Style.dim
                font.family: Style.body
                font.pixelSize: 13
            }
            Rectangle {
                visible: panel.results.length > 0
                Layout.fillWidth: true
                implicitHeight: 1
                color: Style.lineStrong
            }
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.topMargin: -12
                Layout.preferredHeight: Math.min(contentHeight, sheet.parent ? sheet.parent.height - 260 : 400)
                visible: count > 0
                clip: true
                spacing: 0
                model: panel.results
                keyNavigationEnabled: true
                ScrollBar.vertical: ScrollBar {}
                delegate: Rectangle {
                    id: result
                    required property var modelData
                    required property int index
                    readonly property bool current: ListView.isCurrentItem
                    width: ListView.view.width - 10
                    height: resultColumn.implicitHeight + 20
                    color: current ? Style.wash : resultHover.hovered ? Style.raised : "transparent"
                    Rectangle {
                        visible: result.current
                        width: 2
                        height: parent.height
                        color: theme.accent
                    }
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: Style.line
                    }
                    ColumnLayout {
                        id: resultColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 14
                        anchors.rightMargin: 12
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Text {
                                text: result.modelData.codename
                                color: Style.text
                                font.family: Style.mono
                                font.variableAxes: Style.wide
                                font.pixelSize: 13
                                font.letterSpacing: -0.2
                            }
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: "# " + result.modelData.kind + (result.modelData.archived ? qsTr(" · archived") : "")
                                color: Style.dim
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 10
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: result.modelData.snippet
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            color: Style.text2
                            font.family: Style.mono
                            font.variableAxes: Style.narrow
                            font.pixelSize: 11
                            lineHeight: 1.1
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
