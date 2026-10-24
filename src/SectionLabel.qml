import QtQuick
import QtQuick.Layouts

// A small all-caps heading with a tick and a rule running off to the right.
RowLayout {
    property string text
    property string detail
    spacing: 10
    Rectangle { implicitWidth: 3; implicitHeight: 12; color: theme.accent }
    Text {
        text: parent.text
        color: Style.text
        font.family: Style.display
        font.pixelSize: 12
        font.weight: Font.Bold
        font.letterSpacing: 4
        font.capitalization: Font.AllUppercase
    }
    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }
    Text {
        visible: text.length > 0
        text: parent.detail
        color: Style.dim
        font.family: Style.mono
        font.pixelSize: 11
        font.letterSpacing: 1
    }
}
