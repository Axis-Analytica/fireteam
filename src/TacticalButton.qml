import QtQuick
import QtQuick.Layouts

// A moulded key: square, a lit top edge and a shaded bottom one, sinking a
// pixel when pressed. The primary is the accent with ink on it. State changes
// switch at once rather than fading, as a terminal would.
Item {
    id: button
    property string text
    property string key
    property bool primary: false
    property bool danger: false
    signal clicked()

    readonly property color fill: primary ? (danger ? Style.danger : theme.accent)
                                : hover.hovered && enabled ? Style.raised : Style.panel
    readonly property color ink: primary ? (danger ? "#140606" : theme.accentForeground)
                               : danger ? Style.danger : Style.text

    implicitWidth: row.implicitWidth + 32
    implicitHeight: 40
    opacity: enabled ? 1 : 0.4

    Rectangle {
        id: cap
        anchors.fill: parent
        anchors.topMargin: tap.pressed ? 1 : 0
        anchors.bottomMargin: tap.pressed ? -1 : 0
        color: button.fill
        radius: Math.min(4, theme.radius)
        border.color: button.primary ? Qt.darker(button.fill, 1.35)
                    : hover.hovered && button.enabled ? (button.danger ? Style.danger : Style.text2) : Style.lineStrong
        // The lit top edge and the shaded bottom one.
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: 1
            height: 1
            color: Qt.rgba(1, 1, 1, button.primary ? 0.32 : 0.07)
        }
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.margins: 1
            height: 1
            color: Qt.rgba(0, 0, 0, tap.pressed ? 0 : 0.35)
        }
        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 10
            Text {
                visible: button.key.length > 0
                text: button.key
                color: button.ink
                opacity: 0.6
                font.family: Style.mono
                font.variableAxes: Style.narrow
                font.pixelSize: 11
            }
            Text {
                text: button.text
                color: button.ink
                font.family: Style.body
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
        }
    }
    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: if (hovered && button.enabled) Sfx.play("tick")
    }
    TapHandler { id: tap; onTapped: if (button.enabled) button.clicked() }
}
