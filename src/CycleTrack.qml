import QtQuick
import QtQuick.Layouts

// One square segment per cycle: filled when done, pulsing while in action.
RowLayout {
    id: track
    property int cycles: 1
    property int done: 0
    property bool live: false
    property int segmentHeight: 14
    property bool labels: true
    spacing: 3

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
                    readonly property bool current: track.live && index === track.done
                    color: index < track.done || current ? theme.accent : Style.line
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
                color: index < track.done ? Style.text2 : Style.faint
                font.family: Style.mono
                font.variableAxes: Style.narrow
                font.pixelSize: 10
            }
        }
    }
}
