import QtQuick

// A small bordered tag: status, rules of engagement, model, path.
Rectangle {
    id: chip
    property string text
    property color tone: Style.dim
    property bool solid: false
    property bool mono: false
    implicitWidth: Math.min(label.implicitWidth + 20, 520)
    implicitHeight: 24
    radius: Math.min(4, theme.radius)
    color: solid ? tone : "transparent"
    border.color: solid ? tone : Qt.rgba(tone.r, tone.g, tone.b, 0.5)
    Text {
        id: label
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        verticalAlignment: Text.AlignVCenter
        text: chip.text
        elide: Text.ElideMiddle
        color: chip.solid ? (chip.tone === theme.accent ? theme.accentForeground : "#0b0b0b") : chip.tone
        font.family: chip.mono ? Style.mono : Style.display
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: chip.mono ? 0 : 2
        font.capitalization: chip.mono ? Font.MixedCase : Font.AllUppercase
    }
}
