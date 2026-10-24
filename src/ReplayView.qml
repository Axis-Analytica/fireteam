import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// An operation's whole run, replayed from its comms: a scrubber across time,
// cycle and failure markers, and playback at up to 60 times speed.
Item {
    id: replay
    visible: false
    property var op: null
    property var timeline: []
    property real duration: timeline.length > 0 ? timeline[timeline.length - 1].t : 0
    property real position: 0
    property real speed: 10
    property bool playing: false
    // How many lines have happened by the current position.
    readonly property int shown: {
        let low = 0, high = timeline.length
        while (low < high) {
            const mid = (low + high) >> 1
            if (timeline[mid].t <= position) low = mid + 1
            else high = mid
        }
        return low
    }
    readonly property var cycles: timeline.filter(e => e.kind === "sys" && /^Cycle \d+ of \d+ deployed/.test(e.text))
    readonly property var failures: timeline.filter(e => e.kind === "error")

    Material.theme: Material.Dark
    Material.accent: theme.accent

    function open(target, row) {
        op = target
        timeline = ops.replay(row)
        position = 0
        playing = timeline.length > 0
        visible = true
        enter.restart()
    }
    function close() { visible = false; playing = false }
    function clock(seconds) {
        const s = Math.floor(seconds)
        return "T+" + Style.pad(Math.floor(s / 3600)) + ":" + Style.pad(Math.floor(s % 3600 / 60)) + ":" + Style.pad(s % 60)
    }

    Timer {
        interval: 50
        repeat: true
        running: replay.visible && replay.playing
        onTriggered: {
            // Quiet stretches (an agent thinking, a night between cycles) are
            // skipped: playback jumps to just before the next line.
            const next = replay.shown < replay.timeline.length ? replay.timeline[replay.shown].t : replay.duration
            if (next - replay.position > 3 * replay.speed / 10 + 3)
                replay.position = next - 0.5
            replay.position = Math.min(replay.duration, replay.position + 0.05 * replay.speed)
            if (replay.position >= replay.duration)
                replay.playing = false
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.88)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: replay.close() }
    }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(1180, parent.width - 48)
        height: parent.height - 48
        color: Qt.rgba(0.03, 0.035, 0.045, 0.98)
        border.color: Style.line
        radius: theme.radius
        // Clicks on the panel itself mustn't reach the dismissing backdrop.
        MouseArea { anchors.fill: parent }
        Rectangle { width: parent.width; height: 3; color: Style.danger }

        ParallelAnimation {
            id: enter
            NumberAnimation { target: sheet; property: "opacity"; from: 0; to: 1; duration: 160 }
            NumberAnimation { target: sheet; property: "scale"; from: 1.02; to: 1; duration: 260; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 16
                ColumnLayout {
                    spacing: 2
                    Text {
                        text: qsTr("After-action replay")
                        color: Style.danger
                        font.family: Style.mono
                        font.pixelSize: 11
                        font.letterSpacing: 4 * Style.tracking
                        font.capitalization: Font.AllUppercase
                    }
                    Text {
                        text: replay.op ? replay.op.codename : ""
                        color: Style.text
                        font.family: Style.display
                        font.pixelSize: 34
                        font.weight: Font.Black
                        font.letterSpacing: 5 * Style.tracking
                    }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: replay.clock(replay.position)
                    color: Style.text
                    font.family: Style.mono
                    font.pixelSize: 28
                    font.bold: true
                }
                Text {
                    text: "/ " + replay.clock(replay.duration)
                    color: Style.faint
                    font.family: Style.mono
                    font.pixelSize: 14
                }
            }

            // The run so far, newest at the bottom.
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Qt.rgba(0, 0, 0, 0.5)
                border.color: Style.line
                radius: theme.radius
                ListView {
                    id: lines
                    anchors.fill: parent
                    anchors.margins: 12
                    clip: true
                    spacing: 5
                    model: replay.timeline.slice(Math.max(0, replay.shown - 300), replay.shown)
                    onCountChanged: positionViewAtEnd()
                    delegate: RowLayout {
                        id: line
                        required property var modelData
                        width: ListView.view.width - 10
                        spacing: 10
                        readonly property color tone: {
                            switch (modelData.kind) {
                            case "error": return Style.danger
                            case "tool": case "report": return theme.accent
                            case "result": case "review": return Style.good
                            case "cmd": case "denied": return Style.amber
                            case "ask": return Style.danger
                            case "sys": return Style.dim
                            }
                            return Style.text
                        }
                        Text {
                            Layout.alignment: Qt.AlignTop
                            text: replay.clock(line.modelData.t)
                            color: Style.faint
                            font.family: Style.mono
                            font.pixelSize: 11
                        }
                        Text {
                            Layout.alignment: Qt.AlignTop
                            Layout.preferredWidth: 60
                            text: line.modelData.kind.toUpperCase()
                            color: line.tone
                            font.family: Style.mono
                            font.pixelSize: 11
                            font.bold: true
                        }
                        Text {
                            Layout.fillWidth: true
                            text: line.modelData.text
                            wrapMode: Text.Wrap
                            maximumLineCount: 6
                            elide: Text.ElideRight
                            color: line.modelData.kind === "say" ? Style.text : line.tone
                            font.family: Style.mono
                            font.pixelSize: 12
                            textFormat: Text.PlainText
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: replay.timeline.length === 0
                    text: qsTr("Nothing recorded to replay")
                    color: Style.faint
                    font.family: Style.display
                    font.pixelSize: 14
                    font.letterSpacing: 4 * Style.tracking
                    font.capitalization: Font.AllUppercase
                }
            }

            // The scrubber, with a tick per cycle and a red one per failure.
            Item {
                Layout.fillWidth: true
                implicitHeight: 34
                Rectangle {
                    id: track
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 6
                    color: Qt.rgba(1, 1, 1, 0.08)
                    radius: 3
                    Rectangle {
                        width: replay.duration > 0 ? parent.width * replay.position / replay.duration : 0
                        height: parent.height
                        radius: 3
                        color: Style.danger
                    }
                }
                Repeater {
                    model: replay.cycles
                    delegate: Rectangle {
                        required property var modelData
                        x: replay.duration > 0 ? track.width * modelData.t / replay.duration - 1 : 0
                        y: track.y - 7
                        width: 2
                        height: track.height + 14
                        color: Style.text
                        opacity: 0.7
                    }
                }
                Repeater {
                    model: replay.failures
                    delegate: Rectangle {
                        required property var modelData
                        x: replay.duration > 0 ? track.width * modelData.t / replay.duration - 3 : 0
                        y: track.y + track.height + 4
                        width: 6
                        height: 6
                        radius: 3
                        color: Style.danger
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                    function seek(x) { replay.position = Math.max(0, Math.min(1, x / width)) * replay.duration }
                    onPressed: (mouse) => seek(mouse.x)
                    onPositionChanged: (mouse) => { if (pressed) seek(mouse.x) }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                TacticalButton { text: qsTr("Close"); key: "Esc"; onClicked: replay.close() }
                TacticalButton {
                    text: replay.playing ? qsTr("Pause") : qsTr("Play")
                    key: qsTr("Space")
                    primary: true
                    onClicked: {
                        if (replay.position >= replay.duration) replay.position = 0
                        replay.playing = !replay.playing
                    }
                }
                Item { Layout.fillWidth: true }
                Repeater {
                    model: [1, 10, 60, 300]
                    delegate: TacticalButton {
                        required property int modelData
                        text: modelData + "×"
                        primary: replay.speed === modelData
                        onClicked: replay.speed = modelData
                    }
                }
                Text {
                    text: qsTr("%1 of %2 lines").arg(replay.shown).arg(replay.timeline.length)
                    color: Style.faint
                    font.family: Style.mono
                    font.pixelSize: 11
                }
            }
        }
    }

    Shortcut {
        enabled: replay.visible
        sequence: "Space"
        context: Qt.ApplicationShortcut
        onActivated: { if (replay.position >= replay.duration) replay.position = 0; replay.playing = !replay.playing }
    }
    Shortcut { enabled: replay.visible; sequence: "Left"; context: Qt.ApplicationShortcut; onActivated: replay.position = Math.max(0, replay.position - replay.duration / 50) }
    Shortcut { enabled: replay.visible; sequence: "Right"; context: Qt.ApplicationShortcut; onActivated: replay.position = Math.min(replay.duration, replay.position + replay.duration / 50) }
}
