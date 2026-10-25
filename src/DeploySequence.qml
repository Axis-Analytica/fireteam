import QtQuick

// The insertion screen played when an operation deploys: accent brackets close
// in on the codename, the orders line types out, the codename types in wide
// mono, a radio line follows, a thin meter runs out, and the board returns.
// It's only a show; the agent is already on its way. Any key or click skips it.
Item {
    id: sequence
    visible: false
    property string codename
    property string detail
    property string radio
    property int typed: 0
    property int radioTyped: 0
    property int eyebrowTyped: 0
    property real progress: 0

    readonly property string eyebrow: "# " + qsTr("Insertion // %1").arg(detail).toLowerCase()

    function play(name, line, info) {
        codename = name
        radio = line
        detail = info
        typed = 0
        radioTyped = 0
        eyebrowTyped = 0
        progress = 0
        visible = true
        Sfx.play("deploy")
        run.restart()
        forceActiveFocus()
    }
    function skip() {
        run.stop()
        finish.restart()
    }

    Keys.onPressed: (event) => { event.accepted = true; sequence.skip() }
    MouseArea { anchors.fill: parent; onClicked: sequence.skip() }

    Rectangle { id: shade; anchors.fill: parent; color: Qt.rgba(Style.bg.r, Style.bg.g, Style.bg.b, 1); opacity: 0 }

    // The codename at 100px, to size it so the whole of it fits the frame.
    TextMetrics {
        id: measure
        text: sequence.codename.length > 0 ? sequence.codename : "M"
        font.family: Style.mono
        font.variableAxes: Style.wide
        font.pixelSize: 100
        font.letterSpacing: -0.6
    }

    // The targeting frame: four accent corners that settle on the content.
    Item {
        id: frame
        anchors.centerIn: parent
        width: Math.min(parent.width - 64, 880)
        height: content.implicitHeight + 2 * pad
        readonly property int pad: Math.min(48, width / 14)
        property real spread: 1

        Repeater {
            model: 4
            delegate: Item {
                required property int index
                readonly property bool east: index % 2 === 1
                readonly property bool south: index >= 2
                width: 22
                height: 22
                x: (east ? frame.width - width : 0) + (east ? 1 : -1) * frame.spread * sequence.width * 0.12
                y: (south ? frame.height - height : 0) + (south ? 1 : -1) * frame.spread * sequence.height * 0.12
                opacity: 1 - frame.spread
                Rectangle { x: parent.east ? parent.width - 2 : 0; width: 2; height: parent.height; color: theme.accent }
                Rectangle { y: parent.south ? parent.height - 2 : 0; width: parent.width; height: 2; color: theme.accent }
            }
        }

        Column {
            id: content
            x: frame.pad
            y: frame.pad
            width: frame.width - 2 * frame.pad
            spacing: 0

            // The orders line, typed as a comment.
            Row {
                spacing: 10
                height: 18
                Rectangle { width: 6; height: 6; anchors.verticalCenter: parent.verticalCenter; color: theme.accent }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, content.width - 16)
                    elide: Text.ElideRight
                    text: sequence.eyebrow.slice(0, sequence.eyebrowTyped)
                    color: Style.dim
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 12
                }
            }

            Item { width: 1; height: 14 }

            // The callsign, typed in, with a block cursor in the accent.
            Item {
                width: content.width
                height: callsign.height
                Text {
                    id: callsign
                    text: sequence.codename.slice(0, sequence.typed)
                    color: Style.text
                    font.family: Style.mono
                    font.variableAxes: Style.wide
                    font.letterSpacing: -0.6
                    font.pixelSize: Math.max(22, Math.min(64, 100 * (content.width - 40) / Math.max(1, measure.advanceWidth)))
                    // A steady height, so the lines below don't move as it types.
                    height: font.pixelSize * 1.25
                    verticalAlignment: Text.AlignVCenter
                }
                Rectangle {
                    id: cursor
                    x: callsign.implicitWidth + (sequence.typed > 0 ? 6 : 0)
                    anchors.verticalCenter: callsign.verticalCenter
                    width: Math.round(callsign.font.pixelSize * 0.5)
                    height: Math.round(callsign.font.pixelSize * 0.8)
                    color: theme.accent
                    property bool lit: true
                    visible: lit && sequence.radioTyped === 0
                    Timer {
                        running: sequence.visible && sequence.typed >= sequence.codename.length
                        interval: 260
                        repeat: true
                        onTriggered: cursor.lit = !cursor.lit
                        onRunningChanged: cursor.lit = true
                    }
                }
            }

            Item { width: 1; height: 18 }

            // The radio call, typed out.
            Row {
                spacing: 10
                width: content.width
                Text {
                    id: prompt
                    text: "›"
                    color: theme.accent
                    opacity: sequence.radioTyped > 0 ? 1 : 0
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 14
                }
                Text {
                    width: content.width - prompt.width - 10
                    wrapMode: Text.Wrap
                    text: sequence.radioTyped > 0 ? "“" + sequence.radio.slice(0, sequence.radioTyped) + "”" : " "
                    color: Style.text2
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 14
                }
            }

            Item { width: 1; height: 28 }

            // A thin meter for the show's own length.
            Rectangle {
                width: content.width
                height: 2
                color: Style.line
                Rectangle { width: parent.width * sequence.progress; height: parent.height; color: theme.accent }
            }
        }
    }

    ParallelAnimation {
        id: run
        SequentialAnimation {
            ParallelAnimation {
                NumberAnimation { target: shade; property: "opacity"; from: 0; to: 0.92; duration: 160 }
                NumberAnimation { target: frame; property: "spread"; from: 1; to: 0; duration: 320; easing.type: Easing.OutExpo }
            }
            NumberAnimation { target: sequence; property: "eyebrowTyped"; from: 0; to: sequence.eyebrow.length; duration: 260 }
            NumberAnimation { target: sequence; property: "typed"; from: 0; to: sequence.codename.length; duration: 380 }
            NumberAnimation { target: sequence; property: "radioTyped"; from: 0; to: sequence.radio.length; duration: 560 }
            PauseAnimation { duration: 420 }
            ScriptAction { script: finish.restart() }
        }
        NumberAnimation { target: sequence; property: "progress"; from: 0; to: 1; duration: 1940 }
    }
    SequentialAnimation {
        id: finish
        ParallelAnimation {
            NumberAnimation { target: shade; property: "opacity"; to: 0; duration: 280; easing.type: Easing.InCubic }
            NumberAnimation { target: frame; property: "opacity"; from: 1; to: 0; duration: 200 }
            NumberAnimation { target: frame; property: "spread"; to: 0.15; duration: 280; easing.type: Easing.InCubic }
        }
        ScriptAction { script: { sequence.visible = false; frame.opacity = 1 } }
    }
}
