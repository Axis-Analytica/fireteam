import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Everything about the selected operation: its orders, the live comms feed
// from the agent, the latest sitrep, the debriefs, and the changed files.
Item {
    id: detail
    property var op: null
    property int row: -1
    readonly property bool live: op !== null && op.status === "deployed"
    // In the queue, or held by the plan's usage limit.
    readonly property bool waiting: op !== null && (op.status === "staged" || op.status === "pinned")
    // Below this width the side column moves under the comms.
    readonly property bool compact: width < 760
    // Short of height (a short window, or the authorisation banner showing),
    // the larger pieces shrink.
    readonly property bool tight: height < 720

    signal deployRequested()
    signal abortRequested()
    signal removeRequested()
    signal ordersRequested()
    signal editRequested()
    signal diffRequested(int run)
    signal authorisationRequested()
    signal extractRequested()
    signal replayRequested()
    signal graphRequested()

    Menu {
        id: exportMenu
        MenuItem { text: qsTr("HTML report"); onTriggered: ops.reveal(ops.exportOperation(detail.row, "html")) }
        MenuItem { text: qsTr("Markdown write-up"); onTriggered: ops.reveal(ops.exportOperation(detail.row, "md")) }
    }
    signal discardRequested()

    // Comms filter: all, agent, tools, command, or errors, plus a search.
    property string commsFilter: "all"
    property alias commsQuery: search.text
    function focusSearch() { search.forceActiveFocus(); search.selectAll() }
    function matches(entry) {
        switch (commsFilter) {
        case "agent": if (entry.kind !== "say" && entry.kind !== "result") return false; break
        case "tools": if (entry.kind !== "tool") return false; break
        case "command": if (entry.kind !== "cmd" && entry.kind !== "sys") return false; break
        case "errors": if (entry.kind !== "error" && entry.kind !== "denied") return false; break
        }
        return search.text.length === 0 || entry.text.toLowerCase().indexOf(search.text.toLowerCase()) >= 0
    }

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius

    // The codename settles in whenever the selection changes, its corner
    // marks closing on it like a reticle.
    onOpChanged: if (op) intro.restart()
    ParallelAnimation {
        id: intro
        NumberAnimation { target: title; property: "opacity"; from: 0; to: 1; duration: 180 }
        NumberAnimation { target: title; property: "x"; from: -10; to: 0; duration: 240; easing.type: Easing.OutCubic }
        NumberAnimation { target: reticle; property: "anchors.margins"; from: -14; to: -6; duration: 260; easing.type: Easing.OutCubic }
        NumberAnimation { target: reticle; property: "opacity"; from: 0; to: 1; duration: 200 }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 16
        visible: detail.op !== null

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            GridLayout {
                Layout.fillWidth: true
                columns: detail.compact ? 1 : 2
                columnSpacing: 16
                rowSpacing: 6
                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: detail.op ? qsTr("Operation // %1 · planned %2").arg(detail.op.opId)
                                          .arg(Qt.formatDateTime(detail.op.created, "d MMM HH:mm")) : ""
                    elide: Text.ElideRight
                    color: Style.dim
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 11
                }
                // The less frequent actions, as links, so the main row fits;
                // short of room they wrap onto their own lines.
                Flow {
                    Layout.fillWidth: detail.compact
                    Layout.minimumWidth: 0
                    spacing: 16
                Repeater {
                    model: [
                        { label: qsTr("Replay"), key: "⇧R", action: "replay" },
                        { label: qsTr("Map"), key: "G", action: "graph" },
                        { label: qsTr("Export"), key: "", action: "export" },
                        { label: detail.op && detail.op.archived ? qsTr("Unarchive") : qsTr("Archive"), key: "", action: "archive" },
                        { label: qsTr("Authorised"), key: "A", action: "authorise" },
                        { label: qsTr("Dossier"), key: "D", action: "dossier" },
                        { label: qsTr("Project"), key: "O", action: "project" },
                        { label: qsTr("Stand down"), key: qsTr("Del"), action: "remove" }
                    ]
                    delegate: Text {
                        id: link
                        required property var modelData
                        readonly property bool usable: modelData.action === "dossier" ? detail.op && detail.op.dossier.length > 0
                                                     : modelData.action === "remove" ? detail.op && !detail.live
                                                     : modelData.action === "archive" ? detail.op && !detail.live && !detail.waiting
                                                     : detail.op !== null
                        text: modelData.label + "  <font color=\"" + Style.faint + "\">" + modelData.key + "</font>"
                        textFormat: Text.StyledText
                        opacity: usable ? 1 : 0.35
                        color: linkHover.hovered && usable ? (modelData.action === "remove" ? Style.danger : theme.accent) : Style.text2
                        font.family: Style.body
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        HoverHandler { id: linkHover; cursorShape: link.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
                        TapHandler {
                            enabled: link.usable
                            onTapped: {
                                if (link.modelData.action === "replay") detail.replayRequested()
                                else if (link.modelData.action === "graph") detail.graphRequested()
                                else if (link.modelData.action === "export") exportMenu.popup(link, 0, link.height + 4)
                                else if (link.modelData.action === "archive") ops.setArchived(detail.row, !detail.op.archived)
                                else if (link.modelData.action === "authorise") detail.authorisationRequested()
                                else if (link.modelData.action === "dossier") ops.openDossier(detail.row)
                                else if (link.modelData.action === "project") ops.openProject(detail.row)
                                else detail.removeRequested()
                            }
                        }
                    }
                }
            }
            }
            Item {
                Layout.fillWidth: true
                Layout.topMargin: 4
                implicitHeight: title.implicitHeight
                Text {
                    id: title
                    width: parent.width
                    leftPadding: 10
                    topPadding: 6
                    bottomPadding: 6
                    text: detail.op ? detail.op.codename : ""
                    elide: Text.ElideRight
                    color: Style.text
                    font.family: Style.mono
                    font.variableAxes: Style.wide
                    font.pixelSize: detail.compact || detail.tight ? 30 : 42
                    font.weight: Font.Medium
                    font.letterSpacing: -1
                    rightPadding: leftPadding
                    // Around the codename itself, on whichever side the text sits
                    // (codenames stay left to right in a mirrored window).
                    Brackets {
                        id: reticle
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.margins: -6
                        width: Math.min(parent.width, parent.contentWidth + 2 * parent.leftPadding) + 12
                        x: parent.effectiveHorizontalAlignment === Text.AlignRight ? parent.width - width + 6 : -6
                        size: 10
                    }
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 8
            Chip {
                text: detail.op ? Style.statusLabel(detail.op.status) : ""
                tone: detail.op ? Style.statusColor(detail.op.status, theme.accent) : Style.dim
                solid: true
            }
            Chip {
                text: !detail.op ? "" : detail.op.roe === "free" ? qsTr("ROE · weapons free")
                    : detail.op.roe === "supervised" ? qsTr("ROE · supervised") : qsTr("ROE · restricted")
                tone: detail.op && detail.op.roe === "free" ? Style.danger : detail.op && detail.op.roe === "supervised" ? theme.accent : Style.dim
                marked: true
            }
            Chip { text: detail.op && detail.op.model ? detail.op.model : qsTr("Default model"); tone: Style.dim }
            Chip {
                // claude reports what the run would cost at API prices; on a
                // subscription it counts against the plan's usage, not a bill.
                text: detail.op ? qsTr("≈ $%1 API value").arg(detail.op.cost.toLocaleString(Qt.locale(), 'f', 2)) : ""
                tone: Style.dim
            }
            Chip {
                visible: detail.op !== null && detail.op.orders.length > 0
                text: detail.op ? qsTr("%n order(s) queued", "", detail.op.orders.length) : ""
                tone: Style.amber
                marked: true
            }
            Chip {
                visible: detail.live && detail.op.hold
                text: qsTr("Holding after this cycle")
                tone: Style.amber
                solid: true
            }
            // The latest gates: all green, or how many failed.
            Chip {
                readonly property var gates: detail.op ? detail.op.lastGates : []
                readonly property int passed: gates.filter(g => g.passed).length
                visible: gates.length > 0
                text: passed === gates.length ? qsTr("Gates ✓ %1/%2").arg(passed).arg(gates.length)
                                              : qsTr("Gates ✕ %1/%2").arg(passed).arg(gates.length)
                tone: passed === gates.length ? Style.good : Style.danger
                marked: true
                solid: passed < gates.length
            }
            // The latest overwatch verdict; opens the review.
            Chip {
                id: verdict
                readonly property var review: detail.op && detail.op.reviews.length > 0 ? detail.op.reviews[detail.op.reviews.length - 1] : null
                visible: review !== null || (detail.op !== null && detail.op.overwatch !== "off")
                text: review ? qsTr("Overwatch · %1 ↗").arg(Style.gradeLabel(review.grade))
                             : qsTr("Overwatch · %1").arg(detail.op && detail.op.overwatch === "fix" ? qsTr("review and fix") : qsTr("review"))
                tone: review ? Style.gradeColor(review.grade) : Style.dim
                marked: true
                HoverHandler { cursorShape: verdict.review ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { enabled: verdict.review !== null; onTapped: ops.openReport(verdict.review.file) }
            }
            Chip {
                visible: detail.op !== null && detail.op.worktree
                text: !detail.op ? "" : detail.op.branch.length > 0 ? "⎇ " + detail.op.branch : qsTr("⎇ Own worktree on deploy")
                tone: Style.text2
                mono: true
            }
            Chip { text: detail.op ? detail.op.directory : ""; tone: Style.dim; mono: true }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            SectionLabel {
                Layout.fillWidth: true
                text: qsTr("Cycles")
                detail: detail.op ? qsTr("%1 of %2 complete").arg(detail.op.cyclesDone).arg(detail.op.cycles) : ""
            }
            CycleTrack {
                Layout.fillWidth: true
                // Short of room, the cards stand in for the track.
                visible: !((detail.compact || detail.tight) && timeline.count > 0)
                cycles: detail.op ? detail.op.cycles : 1
                done: detail.op ? detail.op.cyclesDone : 0
                live: detail.live
            }
            // Every cycle run so far, newest on the right; each opens its diff.
            ListView {
                id: timeline
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                Layout.topMargin: 4
                visible: count > 0
                orientation: ListView.Horizontal
                spacing: 8
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: detail.op ? detail.op.history : []
                onCountChanged: Qt.callLater(positionViewAtEnd)
                delegate: CycleCard {
                    current: index === timeline.count - 1
                    onOpened: detail.diffRequested(index)
                }
            }
            SectionLabel {
                Layout.fillWidth: true
                Layout.topMargin: 6
                text: qsTr("Context")
                detail: !detail.op ? ""
                    : qsTr("%1 / %2 · session %3 · %4").arg(Style.tokens(detail.op.context))
                          .arg(Style.tokens(detail.op.contextWindow)).arg(detail.op.session)
                          .arg(detail.op.handoffAt > 0 ? qsTr("hand off at %1, ceiling %2").arg(Style.tokens(detail.op.handoffAt))
                                                             .arg(Style.tokens(detail.op.ceiling))
                                                       : qsTr("no hand-off"))
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                ContextGauge {
                    Layout.fillWidth: true
                    used: detail.op ? detail.op.context : 0
                    window: detail.op ? detail.op.contextWindow : 1000000
                    line: detail.op ? detail.op.handoffAt : 0
                    ceiling: detail.op ? detail.op.ceiling : 0
                }
                Text {
                    visible: detail.op !== null && detail.op.handoffBrief.length > 0
                    text: qsTr("Handoff brief ↗")
                    color: theme.accent
                    font.family: Style.body
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: ops.openReport(detail.op.handoffBrief) }
                }
            }
            // The agent has stopped mid-cycle for the operator: louder still.
            Rectangle {
                id: waitBanner
                readonly property int count: detail.op ? detail.op.questions.length + detail.op.prompts.length : 0
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: count > 0
                implicitHeight: 48
                color: Qt.rgba(Style.danger.r, Style.danger.g, Style.danger.b, waitHover.hovered ? 0.16 : 0.09)
                border.color: Style.danger
                radius: Math.min(2, theme.radius)
                Rectangle { width: 3; height: parent.height; color: Style.danger }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 10
                    spacing: 12
                    Rectangle {
                        implicitWidth: 8; implicitHeight: 8
                        color: Style.danger
                        SequentialAnimation on opacity {
                            running: waitBanner.visible
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.2; duration: 500 }
                            NumberAnimation { to: 1; duration: 500 }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: !detail.op || waitBanner.count === 0 ? ""
                            : detail.op.questions.length > 0
                              ? qsTr("Waiting on you · %1").arg(detail.op.questions[0].question)
                              : qsTr("Waiting on you · permission for %1").arg(detail.op.prompts[0].summary)
                        elide: Text.ElideRight
                        color: Style.text
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                        font.pixelSize: 12
                        textFormat: Text.PlainText
                    }
                    KeyHint { key: "A"; label: qsTr("Respond") }
                }
                HoverHandler { id: waitHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: detail.authorisationRequested() }
            }
            // Refused commands waiting on the operator, impossible to miss.
            Rectangle {
                id: authBanner
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: detail.op !== null && detail.op.requests.length > 0
                implicitHeight: 44
                color: Qt.rgba(Style.amber.r, Style.amber.g, Style.amber.b, bannerHover.hovered ? 0.15 : 0.08)
                border.color: Style.amber
                radius: Math.min(2, theme.radius)
                Rectangle { width: 3; height: parent.height; color: Style.amber }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 10
                    spacing: 12
                    Text {
                        text: "⚠"
                        color: Style.amber
                        font.pixelSize: 15
                    }
                    Text {
                        Layout.fillWidth: true
                        text: !detail.op || detail.op.requests.length === 0 ? ""
                            : qsTr("%n request(s) for authorisation", "", detail.op.requests.length) + "  ·  "
                              + detail.op.requests.map(r => r.summary).join("   ")
                        elide: Text.ElideRight
                        color: Style.text
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                        font.pixelSize: 12
                        textFormat: Text.PlainText
                    }
                    KeyHint { key: "A"; label: qsTr("Review"); accent: Style.amber }
                }
                HoverHandler { id: bannerHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: detail.authorisationRequested() }
            }
            Text {
                Layout.fillWidth: true
                visible: detail.waiting
                text: !detail.op ? ""
                    : detail.op.status === "pinned"
                      ? qsTr("■ Pinned down by the plan's usage limit · resumes at %1").arg(Qt.formatTime(new Date(detail.op.resumeAt * 1000), "HH:mm"))
                      : qsTr("■ Staged · %1 in the queue · deploys when a slot opens").arg("#" + detail.op.queue)
                elide: Text.ElideRight
                color: Style.amber
                font.family: Style.mono
                font.variableAxes: Style.narrow
                font.pixelSize: 12
            }
            // The agent's own progress report, when it has sent one.
            RowLayout {
                Layout.fillWidth: true
                visible: detail.live && detail.op.progress >= 0
                spacing: 10
                Rectangle {
                    Layout.preferredWidth: 120
                    implicitHeight: 4
                    color: Style.line
                    Rectangle {
                        width: parent.width * Math.max(0, detail.op ? detail.op.progress : 0) / 100
                        height: parent.height
                        color: theme.accent
                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: detail.op ? qsTr("%1% · %2").arg(detail.op.progress).arg(detail.op.progressNote) : ""
                    elide: Text.ElideRight
                    color: Style.dim
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 11
                    textFormat: Text.PlainText
                }
            }
            Text {
                Layout.fillWidth: true
                visible: detail.live
                text: "▸ " + (detail.op && detail.op.activity ? detail.op.activity : qsTr("Awaiting contact…"))
                elide: Text.ElideRight
                color: theme.accent
                font.family: Style.mono
                font.variableAxes: Style.narrow
                font.pixelSize: 12
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: detail.compact ? 1 : 2
            columnSpacing: 18
            rowSpacing: 12

            // Comms: the agent's stream, newest at the bottom.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    // The activity line above already says it's live; this row
                    // stays narrow enough to never widen the panel.
                    SectionLabel {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 40
                        Layout.rightMargin: 8
                        text: qsTr("Comms")
                    }
                    // The filters give way (cut at the edge) before the column widens.
                    Item {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: filters.implicitWidth
                        implicitHeight: 22
                        clip: true
                        Flow {
                            id: filters
                            width: parent.width
                            spacing: 6
                            Repeater {
                                model: [
                                    { key: "all", label: qsTr("All") },
                                    { key: "agent", label: qsTr("Agent") },
                                    { key: "tools", label: qsTr("Tools") },
                                    { key: "command", label: qsTr("HQ") },
                                    { key: "errors", label: qsTr("Errors") }
                                ]
                                delegate: Text {
                                    required property var modelData
                                    readonly property bool chosen: detail.commsFilter === modelData.key
                                    text: modelData.label
                                    color: chosen ? Style.text : filterHover.hovered ? Style.text2 : Style.dim
                                    font.family: Style.body
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    rightPadding: 6
                                    bottomPadding: 4
                                    Rectangle {
                                        visible: parent.chosen
                                        anchors.bottom: parent.bottom
                                        width: parent.width - parent.rightPadding
                                        height: 2
                                        color: theme.accent
                                    }
                                    HoverHandler { id: filterHover }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: detail.commsFilter = modelData.key }
                                }
                            }
                        }
                    }
                    TextField {
                        id: search
                        // It gives way first when the column is narrow.
                        Layout.fillWidth: true
                        Layout.maximumWidth: 140
                        Layout.minimumWidth: 70
                        Layout.preferredHeight: 30
                        placeholderText: qsTr("Search  /")
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                        font.pixelSize: 12
                        topPadding: 4
                        bottomPadding: 4
                        Keys.onEscapePressed: { text = ""; detail.forceActiveFocus() }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: detail.tight ? 80 : 120
                    color: Style.panel
                    border.color: Style.line
                    radius: theme.radius
                    ListView {
                        id: comms
                        anchors.fill: parent
                        anchors.margins: 12
                        clip: true
                        spacing: 6
                        model: !detail.op ? []
                             : detail.commsFilter === "all" && search.text.length === 0 ? detail.op.comms
                             : detail.op.comms.filter(entry => detail.matches(entry))
                        onCountChanged: Qt.callLater(positionViewAtEnd)
                        Component.onCompleted: positionViewAtEnd()
                        ScrollBar.vertical: ScrollBar {}
                        delegate: RowLayout {
                            id: line
                            required property var modelData
                            width: ListView.view.width - 10
                            spacing: 10
                            readonly property color tone: {
                                switch (modelData.kind) {
                                case "error": return Style.danger
                                                case "tool": return Style.text2
                                case "result": return Style.good
                                case "cmd": return Style.amber
                                case "denied": return Style.amber
                                case "review": return Style.good
                                case "report": return theme.accent
                                case "ask": return Style.danger
                                case "sys": return Style.dim
                                }
                                return Style.text
                            }
                            Text {
                                Layout.alignment: Qt.AlignTop
                                text: line.modelData.time
                                color: Style.faint
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 11
                            }
                            Text {
                                Layout.alignment: Qt.AlignTop
                                Layout.preferredWidth: 52
                                text: {
                                    switch (line.modelData.kind) {
                                    case "error": return qsTr("ERR")
                                    case "tool": return qsTr("ACT")
                                    case "result": return qsTr("SITREP")
                                    case "cmd": return qsTr("CMD")
                                    case "denied": return qsTr("BLOCK")
                                    case "review": return qsTr("REVIEW")
                                    case "report": return qsTr("REPORT")
                                    case "ask": return qsTr("ASK")
                                    case "sys": return qsTr("HQ")
                                    }
                                    return qsTr("AGENT")
                                }
                                color: line.modelData.kind === "say" ? theme.accent : line.modelData.kind === "tool" ? Style.dim : line.tone
                                font.family: Style.mono
                                font.variableAxes: Style.narrowMedium
                                font.pixelSize: 11
                            }
                            Text {
                                Layout.fillWidth: true
                                text: line.modelData.text
                                wrapMode: Text.Wrap
                                maximumLineCount: ["say", "cmd", "review", "ask"].indexOf(line.modelData.kind) >= 0 ? 12 : 3
                                elide: Text.ElideRight
                                color: line.modelData.kind === "say" ? Style.text : line.tone
                                font.weight: line.modelData.kind === "cmd" ? Font.Medium : Font.Normal
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 12
                                lineHeight: 1.15
                                textFormat: Text.PlainText
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: comms.count === 0
                        text: detail.op && detail.op.comms.length > 0 ? qsTr("Nothing matches") : qsTr("Radio silence")
                        color: Style.faint
                        font.family: Style.body
                        font.pixelSize: 13
                    }
                }
            }

            ColumnLayout {
                readonly property int sideWidth: detail.compact ? detail.width : Math.round(Math.min(380, detail.width * 0.36))
                Layout.preferredWidth: sideWidth
                Layout.maximumWidth: sideWidth
                Layout.fillWidth: detail.compact
                Layout.fillHeight: !detail.compact
                Layout.maximumHeight: detail.compact ? 190 : Infinity
                // Short of room, the side column gives way (and clips) rather
                // than pushing the actions off the bottom.
                Layout.minimumHeight: 0
                clip: true
                spacing: 8

                SectionLabel { Layout.fillWidth: true; text: qsTr("Objective") }
                Text {
                    id: objectiveText
                    Layout.fillWidth: true
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    text: detail.op ? detail.op.objective : ""
                    wrapMode: Text.Wrap
                    color: Style.text2
                    font.family: Style.body
                    font.pixelSize: 14
                    lineHeight: 1.3
                    textFormat: Text.PlainText
                }

                // Acceptance criteria: open, claimed by the agent, or ruled on
                // by overwatch.
                SectionLabel {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    visible: detail.op !== null && detail.op.criteria.length > 0
                    text: qsTr("Criteria")
                    detail: detail.op ? qsTr("%1 of %2 met").arg(detail.op.criteria.filter(c => c.state === "met").length).arg(detail.op.criteria.length) : ""
                }
                Repeater {
                    model: detail.op ? detail.op.criteria : []
                    delegate: RowLayout {
                        id: criterion
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            Layout.alignment: Qt.AlignTop
                            text: criterion.modelData.state === "met" ? "●" : criterion.modelData.state === "unmet" ? "✕"
                                : criterion.modelData.state === "claimed" ? "◐" : "○"
                            color: criterion.modelData.state === "met" ? Style.good : criterion.modelData.state === "unmet" ? Style.danger
                                 : criterion.modelData.state === "claimed" ? Style.amber : Style.faint
                            font.pixelSize: 12
                        }
                        Text {
                            Layout.fillWidth: true
                            text: criterion.modelData.text
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            color: criterion.modelData.state === "met" ? Style.text2 : Style.dim
                            font.family: Style.body
                            font.pixelSize: 13
                            textFormat: Text.PlainText
                            ToolTip.visible: criterionHover.hovered && (criterion.modelData.note || criterion.modelData.evidence)
                            ToolTip.text: criterion.modelData.note || criterion.modelData.evidence || ""
                            HoverHandler { id: criterionHover }
                        }
                    }
                }

                SectionLabel { Layout.fillWidth: true; Layout.topMargin: 8; text: qsTr("Sitrep") }
                Text {
                    id: sitrepText
                    Layout.fillWidth: true
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    text: detail.op && detail.op.sitrep ? detail.op.sitrep : qsTr("No sitrep yet.")
                    wrapMode: Text.Wrap
                    color: detail.op && detail.op.sitrep ? Style.text2 : Style.faint
                    font.family: Style.body
                    font.pixelSize: 14
                    lineHeight: 1.3
                    textFormat: Text.PlainText
                }

                SectionLabel {
                    Layout.fillWidth: true
                    visible: !detail.compact
                    Layout.topMargin: 8
                    text: qsTr("Debriefs")
                    detail: detail.op ? "" + detail.op.reports.length : ""
                }
                ListView {
                    id: debriefs
                    visible: !detail.compact
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, 150)
                    clip: true
                    interactive: contentHeight > height
                    model: detail.op ? detail.op.reports.slice().reverse() : []
                    delegate: Item {
                        id: debrief
                        required property string modelData
                        required property int index
                        width: ListView.view.width
                        height: 30
                        Rectangle {
                            anchors.fill: parent
                            color: debriefHover.hovered ? Style.panel : "transparent"
                            border.color: debriefHover.hovered ? Style.line : "transparent"
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            Text {
                                text: Style.pad(detail.op.reports.length - debrief.index)
                                color: theme.accent
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 11
                            }
                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Cycle %1 debrief").arg(Style.pad(detail.op.reports.length - debrief.index))
                                color: Style.text2
                                font.family: Style.body
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }
                            Text { text: "↗"; color: Style.dim; font.pixelSize: 13 }
                        }
                        HoverHandler { id: debriefHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: ops.openReport(debrief.modelData) }
                    }
                }
                Text {
                    visible: debriefs.count === 0 && !detail.compact
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: qsTr("Debriefs land here as each cycle completes.")
                    color: Style.faint
                    font.family: Style.body
                    font.pixelSize: 12
                }

                SectionLabel {
                    Layout.fillWidth: true
                    visible: !detail.compact
                    Layout.topMargin: 8
                    text: qsTr("Intel")
                    detail: detail.op && detail.op.intel.length ? qsTr("%1 changed").arg(detail.op.intel.length) : ""
                }
                ListView {
                    Layout.fillWidth: true
                    visible: !detail.compact
                    Layout.fillHeight: true
                    Layout.minimumHeight: 0
                    clip: true
                    model: detail.op ? detail.op.intel : []
                    ScrollBar.vertical: ScrollBar {}
                    delegate: Text {
                        required property string modelData
                        width: ListView.view.width - 10
                        text: modelData
                        elide: Text.ElideMiddle
                        color: modelData.startsWith("??") || modelData.startsWith("A") ? Style.text : modelData.startsWith(" D") || modelData.startsWith("D") ? Style.danger : Style.text2
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                        font.pixelSize: 11
                    }
                    Text {
                        visible: parent.count === 0
                        text: qsTr("No changed files reported by git.")
                        color: Style.faint
                        font.family: Style.body
                        font.pixelSize: 12
                    }
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            Layout.preferredHeight: childrenRect.height
            spacing: 10
            TacticalButton {
                visible: !detail.live && !detail.waiting
                text: !detail.op ? qsTr("Deploy")
                    : detail.op.status === "failed" ? qsTr("Retry cycle %1").arg(detail.op.cyclesDone + 1)
                    : detail.op.cyclesDone >= detail.op.cycles ? qsTr("Redeploy +1")
                    : detail.op.cyclesDone > 0 ? qsTr("Resume") : qsTr("Deploy")
                key: qsTr("Space")
                primary: true
                enabled: detail.op !== null
                onClicked: detail.deployRequested()
            }
            TacticalButton {
                text: qsTr("Orders")
                key: "T"
                enabled: detail.op !== null
                onClicked: detail.ordersRequested()
            }
            TacticalButton {
                visible: detail.live
                text: detail.op && detail.op.hold ? qsTr("Lift hold") : qsTr("Hold")
                key: "H"
                onClicked: ops.setHold(detail.row, !detail.op.hold)
            }
            TacticalButton {
                visible: detail.live || detail.waiting
                text: detail.waiting ? qsTr("Leave queue") : qsTr("Abort")
                key: "X"
                danger: true
                onClicked: detail.abortRequested()
            }
            TacticalButton {
                visible: !detail.live
                text: qsTr("Amend")
                key: "E"
                enabled: detail.op !== null
                onClicked: detail.editRequested()
            }
            TacticalButton {
                text: qsTr("Intel")
                key: "V"
                enabled: detail.op !== null && detail.op.history.length > 0
                onClicked: detail.diffRequested(detail.op.history.length - 1)
            }
            TacticalButton {
                visible: detail.op !== null && detail.op.branch.length > 0 && !detail.live && !detail.waiting
                text: qsTr("Extract")
                primary: detail.op !== null && detail.op.status === "complete"
                onClicked: detail.extractRequested()
            }
            TacticalButton {
                visible: detail.op !== null && detail.op.branch.length > 0 && !detail.live && !detail.waiting
                text: qsTr("Discard")
                danger: true
                onClicked: detail.discardRequested()
            }
        }
    }

    // Nothing selected: point at the one thing to do.
    ColumnLayout {
        anchors.centerIn: parent
        visible: detail.op === null
        spacing: 14
        Crosshair { Layout.alignment: Qt.AlignHCenter }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("No operations on the board")
            color: Style.text
            font.family: Style.display
            font.pixelSize: 28
            font.weight: Font.DemiBold
            font.letterSpacing: -0.6
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Plan one and send a fireteam of Claude Code agents in.")
            color: Style.dim
            font.family: Style.body
            font.pixelSize: 14
        }
        KeyHint { Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 8; key: "N"; label: qsTr("Plan operation") }
    }
}
