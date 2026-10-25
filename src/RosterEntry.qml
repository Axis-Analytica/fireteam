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
    required property int progress
    required property string progressNote
    required property var questions
    required property var prompts
    required property string campaign
    required property var gates
    required property var criteria
    required property var preview
    required property var lastGates
    required property bool archived
    required property var controls
    // The agent CLI it runs on: "claude", "codex", "gemini" or "opencode".
    required property string engine
    // Archived operations stay in the model but off the board, unless asked.
    readonly property bool hidden: (archived && !win.showArchived) || win.pendingRemoval === opId
    readonly property int waitingOn: questions.length + prompts.length

    readonly property bool selected: ListView.isCurrentItem
    readonly property color tone: Style.statusColor(status, theme.accent)
    signal activated()

    width: ListView.view ? ListView.view.width : 360
    visible: !hidden
    height: hidden ? 0 : campaign.length > 0 ? 96 : 80
    opacity: archived ? 0.55 : 1

    // Selected: a wash of the accent, a rule down the leading edge, and corner
    // marks. Hover lifts the row a step. Both switch at once.
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 3
        anchors.bottomMargin: 3
        color: entry.selected ? Style.wash : hover.hovered ? Style.panel : "transparent"
        Rectangle {
            visible: entry.selected
            width: 2
            height: parent.height
            color: theme.accent
        }
        Brackets {
            anchors.fill: parent
            visible: entry.selected
            size: 7
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 16
        anchors.topMargin: 13
        anchors.bottomMargin: 12
        spacing: 4

        RowLayout {
            spacing: 10
            Rectangle {
                id: dot
                implicitWidth: 7
                implicitHeight: 7
                color: entry.tone
                SequentialAnimation on opacity {
                    running: entry.status === "deployed" && !Prefs.reduceMotion
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
                color: entry.selected ? Style.text : Style.text2
                font.family: Style.mono
                font.variableAxes: Style.wide
                font.pixelSize: 17
                font.weight: Font.Medium
                font.letterSpacing: -0.3
            }
            ActivityPulse {
                visible: entry.status === "deployed"
                Layout.preferredWidth: 64
                Layout.preferredHeight: 16
                events: entry.events
                live: entry.status === "deployed"
                tone: theme.accent
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            // Only the engines that aren't Claude Code get a tag.
            Rectangle {
                visible: entry.engine.length > 0 && entry.engine !== "claude"
                implicitWidth: engineTag.implicitWidth + 8
                implicitHeight: engineTag.implicitHeight + 2
                color: "transparent"
                border.color: Style.line
                radius: Math.min(2, theme.radius)
                Text {
                    id: engineTag
                    anchors.centerIn: parent
                    text: entry.engine
                    color: Style.text2
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 9
                }
            }
            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: entry.waitingOn > 0
                      ? qsTr("◉ Waiting on you · %1").arg(entry.questions.length > 0 ? qsTr("question") : qsTr("permission"))
                      : entry.requests.length > 0
                      ? qsTr("⚠ Awaiting authorisation · %1").arg(entry.requests.length)
                      : entry.status === "deployed" && entry.activity.length > 0
                      ? entry.activity
                      : entry.status === "staged" ? qsTr("Staged · #%1 in queue · cycle %2/%3").arg(entry.queue).arg(entry.cyclesDone).arg(entry.cycles)
                      : entry.status === "pinned" ? qsTr("Pinned down · resumes %1").arg(Qt.formatTime(new Date(entry.resumeAt * 1000), "HH:mm"))
                      : qsTr("%1 · cycle %2/%3 · ctx %4 · ≈$%5").arg(entry.hold && entry.status === "deployed" ? qsTr("Holding next") : Style.statusLabel(entry.status))
                            .arg(entry.cyclesDone).arg(entry.cycles).arg(Style.tokens(entry.context))
                            .arg(entry.cost.toLocaleString(Qt.locale(), 'f', 2))
                color: entry.waitingOn > 0 ? Style.danger : entry.requests.length > 0 ? Style.amber : Style.dim
                font.family: Style.mono
                font.variableAxes: Style.narrow
                font.pixelSize: 11
            }
        }
        Text {
            Layout.fillWidth: true
            visible: entry.campaign.length > 0
            text: "◆ " + entry.campaign
            elide: Text.ElideRight
            color: Style.text2
            font.family: Style.mono
            font.variableAxes: Style.narrow
            font.pixelSize: 10
        }
        CycleTrack {
            Layout.fillWidth: true
            Layout.topMargin: 3
            cycles: entry.cycles
            done: entry.cyclesDone
            live: entry.status === "deployed"
            segmentHeight: 2
            labels: false
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: if (hovered && !entry.selected) Sfx.play("tick")
    }
    TapHandler { onTapped: entry.activated() }
}
