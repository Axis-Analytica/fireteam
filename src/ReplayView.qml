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
        color: Qt.rgba(Style.bg.r, Style.bg.g, Style.bg.b, 0.86)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: replay.close() }
    }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(1180, parent.width - 48)
        height: parent.height - 48
        color: Style.panel
        border.color: Style.lineStrong
        radius: theme.radius
        // Clicks on the panel itself mustn't reach the dismissing backdrop.
        MouseArea { anchors.fill: parent }
        Brackets { anchors.fill: parent; anchors.margins: -1; size: 12 }

        ParallelAnimation {
            id: enter
            NumberAnimation { target: sheet; property: "opacity"; from: 0; to: 1; duration: 140 }
            NumberAnimation { target: sheet; property: "anchors.verticalCenterOffset"; from: 8; to: 0; duration: 140; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 16

            // Eyebrow and codename; the playhead's clock against the run's length.
            RowLayout {
                Layout.fillWidth: true
                spacing: 16
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Text {
                        Layout.fillWidth: true
                        text: "# " + qsTr("After-action replay").toLowerCase()
                        elide: Text.ElideRight
                        color: Style.dim
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                        font.pixelSize: 11
                    }
                    Text {
                        Layout.fillWidth: true
                        text: replay.op ? replay.op.codename : ""
                        elide: Text.ElideRight
                        color: Style.text
                        font.family: Style.mono
                        font.variableAxes: Style.wide
                        font.pixelSize: 28
                        font.letterSpacing: -0.8
                    }
                }
                ColumnLayout {
                    Layout.alignment: Qt.AlignBottom
                    spacing: 2
                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: replay.clock(replay.position)
                        color: replay.playing ? Style.text : Style.text2
                        font.family: Style.mono
                        font.variableAxes: Style.figure
                        font.pixelSize: 28
                        font.features: { "tnum": 1 }
                    }
                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: "/ " + replay.clock(replay.duration)
                        color: Style.dim
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                        font.pixelSize: 10
                        font.features: { "tnum": 1 }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }

            // The run so far, newest at the bottom.
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Style.bg
                border.color: Style.line
                radius: Math.min(2, theme.radius)
                ListView {
                    id: lines
                    anchors.fill: parent
                    anchors.margins: 14
                    clip: true
                    spacing: 4
                    model: replay.timeline.slice(Math.max(0, replay.shown - 300), replay.shown)
                    onCountChanged: positionViewAtEnd()
                    delegate: RowLayout {
                        id: line
                        required property var modelData
                        width: ListView.view.width - 10
                        spacing: 12
                        readonly property color tone: {
                            switch (modelData.kind) {
                            case "error": return Style.danger
                            case "tool": case "report": return theme.accent
                            case "result": case "review": return Style.good
                            case "cmd": case "denied": return Style.amber
                            case "ask": return Style.danger
                            case "sys": return Style.dim
                            }
                            return Style.text2
                        }
                        Text {
                            Layout.alignment: Qt.AlignTop
                            text: replay.clock(line.modelData.t)
                            color: Style.faint
                            font.family: Style.mono
                            font.variableAxes: Style.narrow
                            font.pixelSize: 11
                            font.features: { "tnum": 1 }
                        }
                        Text {
                            Layout.alignment: Qt.AlignTop
                            Layout.preferredWidth: 54
                            text: line.modelData.kind
                            color: line.tone
                            font.family: Style.mono
                            font.variableAxes: Style.narrowMedium
                            font.pixelSize: 11
                        }
                        Text {
                            Layout.fillWidth: true
                            text: line.modelData.text
                            wrapMode: Text.Wrap
                            maximumLineCount: 6
                            elide: Text.ElideRight
                            color: line.modelData.kind === "say" ? Style.text
                                 : line.modelData.kind === "sys" ? Style.dim
                                 : line.modelData.kind === "error" || line.modelData.kind === "ask" ? Style.danger
                                 : Style.text2
                            font.family: Style.mono
                            font.variableAxes: Style.narrow
                            font.pixelSize: 12
                            textFormat: Text.PlainText
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: replay.timeline.length === 0
                    text: qsTr("Nothing recorded to replay")
                    color: Style.dim
                    font.family: Style.body
                    font.pixelSize: 14
                }
            }

            // The scrubber, with a tick per cycle and a red square per failure.
            Item {
                Layout.fillWidth: true
                implicitHeight: 30
                Rectangle {
                    id: track
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4
                    color: Style.line
                    Rectangle {
                        width: replay.duration > 0 ? parent.width * replay.position / replay.duration : 0
                        height: parent.height
                        color: theme.accent
                    }
                }
                Repeater {
                    model: replay.cycles
                    delegate: Rectangle {
                        required property var modelData
                        x: replay.duration > 0 ? Math.round(track.width * modelData.t / replay.duration) - 1 : 0
                        y: track.y - 6
                        width: 2
                        height: track.height + 12
                        color: Style.text2
                    }
                }
                Repeater {
                    model: replay.failures
                    delegate: Rectangle {
                        required property var modelData
                        x: replay.duration > 0 ? Math.round(track.width * modelData.t / replay.duration) - 3 : 0
                        y: track.y + track.height + 5
                        width: 6
                        height: 6
                        color: Style.danger
                    }
                }
                // The playhead.
                Rectangle {
                    x: (replay.duration > 0 ? Math.round(track.width * replay.position / replay.duration) : 0) - 1
                    y: track.y - 8
                    width: 2
                    height: track.height + 16
                    color: Style.text
                }
                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                    cursorShape: Qt.PointingHandCursor
                    function seek(x) { replay.position = Math.max(0, Math.min(1, x / width)) * replay.duration }
                    onPressed: (mouse) => seek(mouse.x)
                    onPositionChanged: (mouse) => { if (pressed) seek(mouse.x) }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }

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
                Text {
                    Layout.rightMargin: 6
                    text: qsTr("%1 of %2 lines").arg(replay.shown).arg(replay.timeline.length)
                    elide: Text.ElideRight
                    Layout.maximumWidth: 200
                    color: Style.dim
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 11
                    font.features: { "tnum": 1 }
                }
                // Playback speed, as a row of segments: the current one washed
                // and underlined in the accent.
                Rectangle {
                    implicitWidth: speeds.implicitWidth + 2
                    implicitHeight: 40
                    color: Style.panel
                    border.color: Style.lineStrong
                    radius: Math.min(2, theme.radius)
                    Row {
                        id: speeds
                        x: 1
                        y: 1
                        Repeater {
                            model: [1, 10, 60, 300]
                            delegate: Rectangle {
                                id: speed
                                required property int modelData
                                required property int index
                                readonly property bool current: replay.speed === modelData
                                width: Math.max(48, speedLabel.implicitWidth + 24)
                                height: 38
                                color: current ? Style.wash : speedHover.hovered ? Style.raised : "transparent"
                                Rectangle {
                                    visible: speed.index > 0
                                    width: 1
                                    height: parent.height
                                    color: Style.line
                                }
                                Text {
                                    id: speedLabel
                                    anchors.centerIn: parent
                                    text: speed.modelData + "×"
                                    color: speed.current ? Style.text : Style.dim
                                    font.family: Style.mono
                                    font.variableAxes: Style.narrow
                                    font.pixelSize: 12
                                    font.features: { "tnum": 1 }
                                }
                                Rectangle {
                                    visible: speed.current
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: 2
                                    color: theme.accent
                                }
                                HoverHandler { id: speedHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: replay.speed = speed.modelData }
                            }
                        }
                    }
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
