import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

// An operation in the roster, styled as a game-menu entry: selecting it
// sweeps a slanted accent slab in behind the codename.
Item {
    id: entry
    required property int index
    required property string opId
    required property string codename
    required property string directory
    required property string objective
    required property string model
    required property string roe
    required property int cycles
    required property int cyclesDone
    required property string status
    required property double cost
    required property string sitrep
    required property string activity
    required property var intel
    required property var reports
    required property var comms
    required property string dossier
    required property var created
    required property real context
    required property real contextWindow
    required property real handoffAt
    required property int session
    required property string handoffBrief
    required property var orders
    required property bool hold
    required property real ceiling
    required property var history
    required property bool canUndoRollback
    required property int events
    required property var requests
    required property var allowed
    required property string standing
    required property bool worktree
    required property string workdir
    required property string branch
    required property string baseBranch
    required property real resumeAt
    required property int queue
    required property string overwatch
    required property var reviews

    readonly property bool selected: ListView.isCurrentItem
    readonly property color ink: selected ? theme.accentForeground : Style.text
    signal activated()

    width: ListView.view ? ListView.view.width : 360
    height: 84

    Shape {
        id: slab
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        width: entry.selected ? entry.width : 0
        opacity: entry.selected ? 1 : 0
        Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 140 } }
        ShapePath {
            fillColor: theme.accent
            strokeColor: "transparent"
            startX: 0; startY: 0
            PathLine { x: slab.width; y: 0 }
            PathLine { x: Math.max(0, slab.width - 18); y: slab.height }
            PathLine { x: 0; y: slab.height }
            PathLine { x: 0; y: 0 }
        }
    }
    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: hover.hovered && !entry.selected ? parent.height - 20 : 0
        color: theme.accent
        Behavior on height { NumberAnimation { duration: 120 } }
    }
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        visible: hover.hovered && !entry.selected
        color: Qt.rgba(1, 1, 1, 0.04)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 30
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        spacing: 3

        RowLayout {
            spacing: 10
            Rectangle {
                id: dot
                implicitWidth: 8
                implicitHeight: 8
                radius: 4
                color: entry.selected ? entry.ink : Style.statusColor(entry.status, theme.accent)
                SequentialAnimation on opacity {
                    running: entry.status === "deployed"
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.15; duration: 450 }
                    NumberAnimation { to: 1; duration: 450 }
                    onStopped: dot.opacity = 1
                }
            }
            Text {
                Layout.fillWidth: true
                text: entry.codename
                elide: Text.ElideRight
                color: entry.ink
                font.family: Style.display
                font.pixelSize: 22
                font.weight: Font.Black
                font.letterSpacing: 3 * Style.tracking
            }
            ActivityPulse {
                visible: entry.status === "deployed"
                Layout.preferredWidth: 64
                Layout.preferredHeight: 16
                events: entry.events
                live: entry.status === "deployed"
                tone: entry.selected ? entry.ink : theme.accent
            }
        }
        Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: entry.requests.length > 0
                  ? qsTr("⚠ Awaiting authorisation · %1").arg(entry.requests.length)
                  : entry.status === "deployed" && entry.activity.length > 0
                  ? entry.activity
                  : entry.status === "staged" ? qsTr("STAGED · #%1 in queue · cycle %2/%3").arg(entry.queue).arg(entry.cyclesDone).arg(entry.cycles)
                  : entry.status === "pinned" ? qsTr("PINNED DOWN · resumes %1").arg(Qt.formatTime(new Date(entry.resumeAt * 1000), "HH:mm"))
                  : qsTr("%1 · cycle %2/%3 · ctx %4 · ≈$%5").arg((entry.hold && entry.status === "deployed" ? qsTr("Holding next") : Style.statusLabel(entry.status)).toUpperCase())
                        .arg(entry.cyclesDone).arg(entry.cycles).arg(Style.tokens(entry.context))
                        .arg(entry.cost.toLocaleString(Qt.locale(), 'f', 2))
            color: entry.selected ? entry.ink : entry.requests.length > 0 ? Style.amber : Style.dim
            opacity: entry.selected ? 0.8 : 1
            font.bold: entry.requests.length > 0
            font.family: Style.mono
            font.pixelSize: 11
        }
        CycleTrack {
            Layout.fillWidth: true
            Layout.topMargin: 4
            cycles: entry.cycles
            done: entry.cyclesDone
            live: entry.status === "deployed"
            segmentHeight: 4
            labels: false
            opacity: entry.selected ? 0.0 : 1
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: if (hovered && !entry.selected) Sfx.play("tick")
    }
    TapHandler { onTapped: entry.activated() }
}
