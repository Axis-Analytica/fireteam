import QtQuick

// How full the session's context is, as a thin flat bar with a tick at the
// hand-off line and a red one at the ceiling. It turns amber approaching the
// line and red past it.
Item {
    id: gauge
    property real used: 0
    property real window: 1000000
    property real line: 250000
    // Past this the cycle is stopped and handed off on the spot.
    property real ceiling: 0

    readonly property real fraction: window > 0 ? Math.min(1, used / window) : 0
    readonly property color tone: line > 0 && used >= line ? Style.danger
                                : line > 0 && used >= line * 0.8 ? Style.amber
                                : theme.accent
    implicitHeight: 12

    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 4
        color: Style.line
        Rectangle {
            width: parent.width * gauge.fraction
            height: parent.height
            color: gauge.tone
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }
    }
    // The hand-off line.
    Rectangle {
        visible: gauge.line > 0 && gauge.window > 0
        x: Math.round(parent.width * Math.min(1, gauge.line / gauge.window)) - 1
        anchors.verticalCenter: parent.verticalCenter
        width: 2
        height: parent.height
        color: Style.text2
    }
    // The ceiling.
    Rectangle {
        visible: gauge.ceiling > 0 && gauge.window > 0
        x: Math.round(parent.width * Math.min(1, gauge.ceiling / gauge.window)) - 1
        anchors.verticalCenter: parent.verticalCenter
        width: 2
        height: parent.height
        color: Style.danger
    }
}
