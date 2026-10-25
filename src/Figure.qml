import QtQuick
import QtQuick.Layouts

// A figure as a tool would print it: wide and light, with a "# comment"
// beneath saying what it counts.
ColumnLayout {
    property string value
    property string comment
    property color tone: Style.text
    property int size: 24
    property int alignment: Qt.AlignRight
    spacing: 2
    Text {
        Layout.alignment: parent.alignment
        text: parent.value
        color: parent.tone
        font.family: Style.mono
        font.variableAxes: Style.figure
        font.pixelSize: parent.size
        font.features: { "tnum": 1 }
    }
    Text {
        Layout.alignment: parent.alignment
        text: "# " + parent.comment
        color: Style.dim
        font.family: Style.mono
        font.variableAxes: Style.narrow
        font.pixelSize: 10
    }
}
