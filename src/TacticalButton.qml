import QtQuick
import QtQuick.Layouts

// A menu button: the accent slab sweeps in on hover, with its key beside it.
Item {
    id: button
    property string text
    property string key
    property bool primary: false
    property bool danger: false
    signal clicked()

    readonly property color tone: danger ? Style.danger : theme.accent
    readonly property bool lit: (hover.hovered || primary) && enabled

    implicitWidth: row.implicitWidth + 32
    implicitHeight: 40
    opacity: enabled ? 1 : 0.35

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.color: button.lit ? button.tone : Qt.rgba(1, 1, 1, 0.16)
        radius: Math.min(4, theme.radius)
    }
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: button.lit ? parent.width : 3
        color: button.lit ? button.tone : Qt.rgba(1, 1, 1, 0.3)
        radius: Math.min(4, theme.radius)
        Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 10
        Text {
            visible: button.key.length > 0
            text: button.key
            color: button.lit ? (button.danger ? "white" : theme.accentForeground) : Style.dim
            opacity: 0.75
            font.family: Style.mono
            font.pixelSize: 11
            font.bold: true
        }
        Text {
            text: button.text
            color: button.lit ? (button.danger ? "white" : theme.accentForeground) : Style.text
            font.family: Style.display
            font.pixelSize: 13
            font.weight: Font.Black
            font.letterSpacing: 3
            font.capitalization: Font.AllUppercase
        }
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: if (button.enabled) button.clicked() }
}
