import QtQuick
import QtQuick.Layouts

// One slanted segment per cycle: filled when done, pulsing while in action.
RowLayout {
    id: track
    property int cycles: 1
    property int done: 0
    property bool live: false
    property int segmentHeight: 14
    property bool labels: true
    spacing: 4

    Repeater {
        model: track.cycles
        delegate: ColumnLayout {
            required property int index
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            spacing: 4
            Item {
                Layout.fillWidth: true
                implicitHeight: track.segmentHeight
                Rectangle {
                    id: segment
                    anchors.fill: parent
                    antialiasing: true
                    readonly property bool current: track.live && index === track.done
                    color: index < track.done ? theme.accent : current ? theme.accent : Qt.rgba(1, 1, 1, 0.07)
                    border.color: index < track.done ? "transparent" : Qt.rgba(1, 1, 1, 0.12)
                    transform: Matrix4x4 { matrix: Qt.matrix4x4(1, -0.6, 0, track.segmentHeight * 0.3, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1) }
                    SequentialAnimation on opacity {
                        running: segment.current
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 600; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
                        onStopped: segment.opacity = 1
                    }
                }
            }
            Text {
                visible: track.labels
                text: Style.pad(index + 1)
                color: index < track.done ? Style.text : Style.faint
                font.family: Style.mono
                font.pixelSize: 10
            }
        }
    }
}
