import QtQuick
import QtQuick.Layouts

// "[SPACE] DEPLOY" in the footer style of a game menu.
RowLayout {
    property string key
    property string label
    property color accent: theme.accent
    spacing: 8
    Rectangle {
        implicitWidth: keyText.implicitWidth + 12
        implicitHeight: 20
        color: "transparent"
        border.color: Qt.rgba(1, 1, 1, 0.35)
        radius: Math.min(3, theme.radius)
        Text {
            id: keyText
            anchors.centerIn: parent
            text: parent.parent.key
            color: Style.text
            font.family: Style.mono
            font.pixelSize: 11
            font.bold: true
        }
    }
    Text {
        text: parent.label
        color: Style.dim
        font.family: Style.display
        font.pixelSize: 12
        font.weight: Font.DemiBold
        font.letterSpacing: 2
        font.capitalization: Font.AllUppercase
    }
}
