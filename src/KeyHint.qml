import QtQuick
import QtQuick.Layouts

// A key and what it does, for the footer: a small moulded cap and a label.
RowLayout {
    property string key
    property string label
    property color accent: theme.accent
    spacing: 7
    Rectangle {
        implicitWidth: Math.max(20, keyText.implicitWidth + 10)
        implicitHeight: 20
        color: Style.panel
        border.color: Style.lineStrong
        radius: Math.min(3, theme.radius)
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.margins: 1
            height: 1
            color: Qt.rgba(0, 0, 0, 0.4)
        }
        Text {
            id: keyText
            anchors.centerIn: parent
            text: parent.parent.key
            color: Style.text
            font.family: Style.mono
            font.variableAxes: Style.narrow
            font.pixelSize: 10
        }
    }
    Text {
        text: parent.label
        color: Style.dim
        font.family: Style.body
        font.pixelSize: 12
    }
}
