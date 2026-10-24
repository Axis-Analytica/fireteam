import QtQuick

// How full the session's context is, with a tick at the hand-off line. It
// warms to amber approaching the line and turns red past it.
Item {
    id: gauge
    property real used: 0
    property real window: 1000000
    property real line: 250000

    readonly property real fraction: window > 0 ? Math.min(1, used / window) : 0
    readonly property color tone: line > 0 && used >= line ? Style.danger
                                : line > 0 && used >= line * 0.8 ? Style.amber
                                : theme.accent
    implicitHeight: 8

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(1, 1, 1, 0.07)
        border.color: Qt.rgba(1, 1, 1, 0.12)
    }
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.width * gauge.fraction
        color: gauge.tone
        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 300 } }
    }
    Rectangle {
        visible: gauge.line > 0 && gauge.window > 0
        x: parent.width * Math.min(1, gauge.line / gauge.window) - 1
        y: -4
        width: 2
        height: parent.height + 8
        color: Style.text
    }
}
