import QtQuick

// A small square tag: status, rules of engagement, model, path. A status chip
// leads with a square of its colour; a solid one is a fill with ink on it.
Rectangle {
    id: chip
    property string text
    property color tone: Style.dim
    property bool solid: false
    property bool mono: false
    // Shows the tone as a leading square rather than colouring the text.
    property bool marked: false
    implicitWidth: Math.min(label.implicitWidth + 20 + (marked ? 14 : 0), 520)
    implicitHeight: 24
    radius: Math.min(2, theme.radius)
    color: solid ? tone : Style.panel
    border.color: solid ? tone : Style.line
    Rectangle {
        visible: chip.marked && !chip.solid
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: 6; height: 6
        color: chip.tone
    }
    Text {
        id: label
        anchors.fill: parent
        anchors.leftMargin: chip.marked && !chip.solid ? 24 : 10
        anchors.rightMargin: 10
        verticalAlignment: Text.AlignVCenter
        text: chip.text
        elide: Text.ElideMiddle
        color: chip.solid ? (chip.tone === theme.accent ? theme.accentForeground : "#0d0f0c")
             : chip.marked ? Style.text2 : chip.tone
        font.family: chip.mono ? Style.mono : Style.body
        font.variableAxes: chip.mono ? Style.narrow : ({})
        font.pixelSize: chip.mono ? 11 : 12
        font.weight: chip.mono ? Font.Normal : Font.Medium
    }
}
