import QtQuick

// The insertion screen played when an operation deploys: HUD brackets close in
// on the codename, a radio line types out, a sweep passes, and the board
// returns. It's only a show; the agent is already on its way. Any key or click
// skips it.
Item {
    id: sequence
    visible: false
    property string codename
    property string detail
    property string radio
    property int typed: 0
    property int radioTyped: 0

    function play(name, line, info) {
        codename = name
        radio = line
        detail = info
        typed = 0
        radioTyped = 0
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

    Rectangle { id: shade; anchors.fill: parent; color: "#020304"; opacity: 0 }

    // The four corners of a targeting frame.
    Item {
        id: frame
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 760)
        height: 220
        property real spread: 1
        Repeater {
            model: 4
            delegate: Item {
                required property int index
                readonly property bool east: index % 2 === 1
                readonly property bool south: index >= 2
                width: 44
                height: 44
                x: (east ? frame.width - width : 0) + (east ? 1 : -1) * frame.spread * sequence.width * 0.3
                y: (south ? frame.height - height : 0) + (south ? 1 : -1) * frame.spread * sequence.height * 0.3
                opacity: 1 - frame.spread * 0.8
                Rectangle { x: parent.east ? parent.width - 3 : 0; width: 3; height: parent.height; color: theme.accent }
                Rectangle { y: parent.south ? parent.height - 3 : 0; width: parent.width; height: 3; color: theme.accent }
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 10
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Insertion // %1").arg(sequence.detail)
                color: theme.accent
                font.family: Style.mono
                font.pixelSize: 12
                font.letterSpacing: 5 * Style.tracking
                font.capitalization: Font.AllUppercase
                opacity: frame.spread < 0.2 ? 1 : 0
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: sequence.codename.slice(0, sequence.typed) + (sequence.typed < sequence.codename.length ? "▌" : "")
                color: Style.text
                font.family: Style.display
                font.pixelSize: Math.min(72, sequence.width / 14)
                font.weight: Font.Black
                font.letterSpacing: 10 * Style.tracking
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: sequence.radioTyped > 0 ? "“" + sequence.radio.slice(0, sequence.radioTyped) + "”" : " "
                color: Style.dim
                font.family: Style.mono
                font.pixelSize: 14
                font.letterSpacing: 1 * Style.tracking
            }
        }
    }

    // The sweep that hands back to the board.
    Rectangle {
        id: sweep
        width: 220
        height: parent.height
        x: -width
        opacity: 0.5
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.85; color: theme.accent }
            GradientStop { position: 1; color: "transparent" }
        }
    }

    SequentialAnimation {
        id: run
        ParallelAnimation {
            NumberAnimation { target: shade; property: "opacity"; from: 0; to: 0.88; duration: 160 }
            NumberAnimation { target: frame; property: "spread"; from: 1; to: 0; duration: 360; easing.type: Easing.OutExpo }
        }
        NumberAnimation { target: sequence; property: "typed"; from: 0; to: sequence.codename.length; duration: 360 }
        NumberAnimation { target: sequence; property: "radioTyped"; from: 0; to: sequence.radio.length; duration: 520 }
        PauseAnimation { duration: 380 }
        ScriptAction { script: finish.restart() }
    }
    SequentialAnimation {
        id: finish
        ParallelAnimation {
            NumberAnimation { target: sweep; property: "x"; from: -sweep.width; to: sequence.width; duration: 320; easing.type: Easing.InOutQuad }
            NumberAnimation { target: shade; property: "opacity"; to: 0; duration: 320 }
            NumberAnimation { target: frame; property: "opacity"; from: 1; to: 0; duration: 220 }
        }
        ScriptAction { script: { sequence.visible = false; frame.opacity = 1 } }
    }
}
