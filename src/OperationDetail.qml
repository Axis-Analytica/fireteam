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
    // The budget and schedule editor, and the in-app reader for a debrief,
    // review or brief.
    signal limitsRequested()
    signal readRequested(string path, string title)
    // The after-action report for a finished operation.
    signal reportRequested()

    Menu {
        id: exportMenu
        MenuItem { text: qsTr("HTML report"); onTriggered: ops.reveal(ops.exportOperation(detail.row, "html")) }
        MenuItem { text: qsTr("Markdown write-up"); onTriggered: ops.reveal(ops.exportOperation(detail.row, "md")) }
    }
    signal discardRequested()

    // Which tab shows below the cycles: comms, brief, proof or history.
    property int tab: 0
    // Wide enough to keep the objective and sitrep beside the comms.
    readonly property bool wide: width > 1100

    // Comms filter: all, agent, tools, command, or errors, plus a search.
    property string commsFilter: "all"
    property alias commsQuery: search.text
    function focusSearch() { tab = 0; search.forceActiveFocus(); search.selectAll() }
    function matches(entry) {
        switch (commsFilter) {
        case "agent": if (entry.kind !== "say" && entry.kind !== "result") return false; break
        case "tools": if (entry.kind !== "tool") return false; break
        case "command": if (entry.kind !== "cmd" && entry.kind !== "sys") return false; break
        case "errors": if (entry.kind !== "error" && entry.kind !== "denied") return false; break
        }
        return search.text.length === 0 || entry.text.toLowerCase().indexOf(search.text.toLowerCase()) >= 0
    }

    // The comms as rows: each line, except that a run of tool calls folds
    // into one row (unless the filter asks for the tools themselves). New
    // lines are appended rather than the list rebuilt, so the view holds
    // still while the operator reads back.
    ListModel { id: commsRows }
    // The filtered lines, and the sequence number of the first of them: rows
    // keep sequence numbers, so lines dropped off the front (the feed keeps
    // the latest few hundred) don't renumber them. Newest row first; the
    // view lays them out bottom to top.
    property var shown: []
    property int shownStart: 0
    property string shownKey: ""
    // Folded runs the operator opened, by their first line.
    property var expanded: ({})
    readonly property var commsSource: op ? op.comms : []
    onCommsSourceChanged: Qt.callLater(refreshComms)
    onCommsFilterChanged: Qt.callLater(refreshComms)
    function sameEntry(a, b) { return a !== undefined && b !== undefined && a.time === b.time && a.kind === b.kind && a.text === b.text }
    function runKey(entry) { return entry.time + "|" + entry.text }
    function entryAt(seq) { return shown[seq - shownStart] }
    function runOf(first, count) { return shown.slice(first - shownStart, first - shownStart + count) }
    function toolSummary(first, count) {
        const names = []
        for (let i = first; i < first + count && names.length < 3; ++i) {
            const text = entryAt(i).text.replace(/\s+/g, " ").trim()
            names.push(text.length > 44 ? text.slice(0, 43) + "…" : text)
        }
        return names.join(", ") + (count > 3 ? ", …" : "")
    }
    function folds(entry, previousKind) { return commsFilter !== "tools" && entry.kind === "tool" && previousKind === "tool" }
    function addEntry(seq) {
        const entry = entryAt(seq)
        if (commsRows.count > 0 && folds(entry, commsRows.get(0).kind)) {
            const first = commsRows.get(0).first
            const count = commsRows.get(0).count + 1
            commsRows.setProperty(0, "count", count)
            commsRows.setProperty(0, "summary", toolSummary(first, count))
            return
        }
        commsRows.insert(0, { first: seq, count: 1, kind: entry.kind, time: entry.time, text: entry.text, summary: "" })
    }
    function dropBefore(start) {
        while (commsRows.count > 0) {
            const last = commsRows.count - 1
            const row = commsRows.get(last)
            if (row.first + row.count <= start) {
                commsRows.remove(last)
                continue
            }
            if (row.first < start) {
                const count = row.first + row.count - start
                const entry = entryAt(start)
                commsRows.set(last, { first: start, count: count, kind: entry.kind, time: entry.time, text: entry.text,
                                      summary: count > 1 ? toolSummary(start, count) : "" })
            }
            break
        }
    }
    function refreshComms() {
        const source = op ? op.comms : []
        const next = commsFilter === "all" && search.text.length === 0 ? source : source.filter(entry => matches(entry))
        const id = op ? op.opId : ""
        const key = id + "|" + commsFilter + "|" + search.text
        const prev = shown
        // The same feed with lines added (and perhaps the oldest dropped):
        // add the new rows and trim the old, leaving the rest in place.
        if (key === shownKey && prev.length > 0 && next.length > 0) {
            let at = -1
            for (let j = next.length - 1; j >= 0; --j) {
                if (sameEntry(next[j], prev[prev.length - 1])) {
                    at = j
                    break
                }
            }
            const dropped = prev.length - 1 - at
            if (at >= 0 && dropped >= 0 && sameEntry(next[0], prev[dropped])) {
                const start = shownStart + dropped
                shown = next
                shownStart = start
                dropBefore(start)
                for (let k = at + 1; k < next.length; ++k)
                    addEntry(start + k)
                return
            }
        }
        if (shownKey.split("|")[0] !== id) {
            expanded = ({})
            comms.following = true
        }
        shownKey = key
        shown = next
        shownStart = 0
        const rows = []
        for (let i = 0; i < next.length; ++i) {
            const entry = next[i]
            if (rows.length > 0 && folds(entry, rows[rows.length - 1].kind)) {
                rows[rows.length - 1].count++
                continue
            }
            rows.push({ first: i, count: 1, kind: entry.kind, time: entry.time, text: entry.text, summary: "" })
        }
        commsRows.clear()
        for (let r = rows.length - 1; r >= 0; --r) {
            if (rows[r].count > 1)
                rows[r].summary = toolSummary(rows[r].first, rows[r].count)
            commsRows.append(rows[r])
        }
        comms.follow()
    }

    // Every operation's id and codename, to name the one a schedule waits on.
    Repeater {
        id: everyOp
        model: ops
        delegate: Item {
            required property string opId
            required property string codename
        }
    }
    function entryOf(id) {
        for (let i = 0; i < everyOp.count; ++i) {
            const item = everyOp.itemAt(i)
            if (item && item.opId === id)
                return item
        }
        return null
    }
    // The budget and schedule.
    readonly property var controls: op && op.controls ? op.controls : ({})
    // The engine it runs on, and overwatch's when that's another one.
    readonly property string engine: op && op.engine ? op.engine : "claude"
    readonly property string reviewEngine: controls.reviewEngine && controls.reviewEngine !== engine ? controls.reviewEngine : ""
    readonly property string reviewModel: controls.reviewModel || ""
    // "Codex · gpt-5" for overwatch on another engine or model; empty otherwise.
    readonly property string reviewOn: (reviewEngine.length > 0 ? engineLabel(reviewEngine) : "")
                                       + (reviewEngine.length > 0 && reviewModel.length > 0 ? " · " : "") + reviewModel
    function engineLabel(key) {
        const found = ops.engines.find(e => e.key === key)
        return found ? found.label
             : ({ claude: "Claude Code", codex: "Codex", gemini: "Gemini CLI", opencode: "OpenCode" })[key] || key
    }

    function duration(seconds) {
        if (seconds < 60) return seconds + "s"
        if (seconds < 3600) return Math.floor(seconds / 60) + "m " + Style.pad(seconds % 60) + "s"
        return Math.floor(seconds / 3600) + "h " + Style.pad(Math.floor(seconds % 3600 / 60)) + "m"
    }
    // A gate's output in a line: its totals if it printed some, else its last line.
    function gateSummary(output) {
        const lines = (output || "").split("\n").map(l => l.trim()).filter(l => l.length > 0)
        for (let i = lines.length - 1; i >= 0; --i)
            if (/(total|passed|failed|error|tests?\b|ok\b)/i.test(lines[i]))
                return lines[i]
        return lines.length > 0 ? lines[lines.length - 1] : ""
    }
    function gateTail(output) {
        const lines = (output || "").split("\n")
        return lines.slice(Math.max(0, lines.length - 16)).join("\n").trim()
    }
    function debriefTitle(cycle) {
        return qsTr("%1 · cycle %2 debrief").arg(op ? op.codename : "").arg(cycle)
    }

    // Ctrl+1…4 pick a tab.
    readonly property bool tabKeys: visible && op !== null && !win.overlayOpen
    Shortcut { sequence: "Ctrl+1"; context: Qt.ApplicationShortcut; enabled: detail.tabKeys; onActivated: detail.tab = 0 }
    Shortcut { sequence: "Ctrl+2"; context: Qt.ApplicationShortcut; enabled: detail.tabKeys; onActivated: detail.tab = 1 }
    Shortcut { sequence: "Ctrl+3"; context: Qt.ApplicationShortcut; enabled: detail.tabKeys; onActivated: detail.tab = 2 }
    Shortcut { sequence: "Ctrl+4"; context: Qt.ApplicationShortcut; enabled: detail.tabKeys; onActivated: detail.tab = 3 }

    // A debrief: reads in the app; the arrow opens it in the browser.
    component DebriefRow: Item {
        id: debrief
        required property string modelData
        required property int index
        readonly property int cycle: detail.op ? detail.op.reports.length - index : 0
        implicitHeight: 30
        Rectangle {
            anchors.fill: parent
            color: debriefHover.hovered ? Style.panel : "transparent"
            border.color: debriefHover.hovered ? Style.line : "transparent"
        }
        HoverHandler { id: debriefHover }
        Item {
            anchors.left: parent.left
            anchors.right: openOut.left
            height: parent.height
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                spacing: 10
                Text {
                    text: Style.pad(debrief.cycle)
                    color: theme.accent
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 11
                }
                Text {
                    Layout.fillWidth: true
                    text: qsTr("Cycle %1 debrief").arg(Style.pad(debrief.cycle))
                    elide: Text.ElideRight
                    color: Style.text2
                    font.family: Style.body
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: detail.readRequested(debrief.modelData, detail.debriefTitle(Style.pad(debrief.cycle))) }
        }
        Text {
            id: openOut
            anchors.right: parent.right
            height: parent.height
            width: 30
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "↗"
            color: outHover.hovered ? theme.accent : Style.dim
            font.pixelSize: 13
            ToolTip.visible: outHover.hovered
            ToolTip.text: qsTr("Open in the browser")
            HoverHandler { id: outHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: ops.openReport(debrief.modelData) }
        }
    }

    // An acceptance criterion: open, claimed by the agent, or ruled on by
    // overwatch; with evidence, its note or evidence beneath.
    component CriterionRow: RowLayout {
        id: criterion
        required property var modelData
        property bool showEvidence: false
        spacing: 8
        Text {
            Layout.alignment: Qt.AlignTop
            text: criterion.modelData.state === "met" ? "●" : criterion.modelData.state === "unmet" ? "✕"
                : criterion.modelData.state === "claimed" ? "◐" : "○"
            color: criterion.modelData.state === "met" ? Style.good : criterion.modelData.state === "unmet" ? Style.danger
                 : criterion.modelData.state === "claimed" ? Style.amber : Style.faint
            font.pixelSize: 12
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
                Layout.fillWidth: true
                text: criterion.modelData.text
                wrapMode: Text.Wrap
                color: criterion.modelData.state === "met" ? Style.text2 : Style.dim
                font.family: Style.body
                font.pixelSize: 13
                textFormat: Text.PlainText
                ToolTip.visible: !criterion.showEvidence && criterionHover.hovered && !!(criterion.modelData.note || criterion.modelData.evidence)
                ToolTip.text: criterion.modelData.note || criterion.modelData.evidence || ""
                HoverHandler { id: criterionHover }
            }
            Text {
                Layout.fillWidth: true
                visible: criterion.showEvidence && text.length > 0
                text: criterion.modelData.note || criterion.modelData.evidence || ""
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
                color: Style.dim
                font.family: Style.mono
                font.variableAxes: Style.narrow
                font.pixelSize: 11
                textFormat: Text.PlainText
            }
        }
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
                        { label: qsTr("Report"), key: "", action: "report" },
                        { label: qsTr("Limits"), key: "B", action: "limits" },
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
                        readonly property bool usable: modelData.action === "report" ? detail.op && detail.op.history.length > 0
                                                     : modelData.action === "dossier" ? detail.op && detail.op.dossier.length > 0
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
                                else if (link.modelData.action === "report") detail.reportRequested()
                                else if (link.modelData.action === "limits") detail.limitsRequested()
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
            Chip { visible: detail.engine !== "claude"; text: detail.engineLabel(detail.engine); tone: Style.text2 }
            Chip { text: detail.op && detail.op.model ? detail.op.model : qsTr("Default model"); tone: Style.dim }
            Chip {
                // claude reports what the run would cost at API prices; on a
                // subscription it counts against the plan's usage, not a bill.
                text: detail.op ? qsTr("≈ $%1 API value").arg(detail.op.cost.toLocaleString(Qt.locale(), 'f', 2)) : ""
                tone: Style.dim
            }
            // The budget, and the share of the plan it may use; either opens the limits.
            Chip {
                id: budgetChip
                readonly property real budget: Number(detail.controls.budgetUsd || 0)
                readonly property real ratio: budget > 0 && detail.op ? detail.op.cost / budget : 0
                visible: budget > 0
                text: !visible ? "" : qsTr("≈$%1 of $%2").arg(detail.op.cost.toLocaleString(Qt.locale(), 'f', 2))
                                                        .arg(budget.toLocaleString(Qt.locale(), 'f', 2))
                tone: ratio >= 1 ? Style.danger : ratio >= 0.8 ? Style.amber : Style.dim
                marked: true
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: detail.limitsRequested() }
            }
            Chip {
                readonly property int plan: Number(detail.controls.budgetPlan || 0)
                visible: plan > 0
                text: qsTr("Plan ≤ %1%").arg(plan)
                tone: Style.dim
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: detail.limitsRequested() }
            }
            Chip {
                readonly property var schedule: detail.controls.schedule || null
                visible: schedule !== null
                text: {
                    if (!schedule)
                        return ""
                    let when = qsTr("after another operation")
                    if (schedule.mode === "time")
                        when = Qt.formatDateTime(new Date(Number(schedule.at) * 1000), "ddd d MMM HH:mm")
                    else if (schedule.mode === "reset")
                        when = qsTr("when usage resets")
                    else {
                        const n = everyOp.count
                        const other = detail.entryOf(schedule.after)
                        if (other)
                            when = qsTr("after %1").arg(other.codename)
                    }
                    return qsTr("Scheduled · %1").arg(when)
                }
                tone: theme.accent
                marked: true
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: detail.limitsRequested() }
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
                // Overwatch on another engine or model says which.
                readonly property string engineNote: detail.reviewOn.length > 0 ? " · " + detail.reviewOn : ""
                text: review ? qsTr("Overwatch · %1 ↗").arg(Style.gradeLabel(review.grade) + engineNote)
                             : qsTr("Overwatch · %1").arg((detail.op && detail.op.overwatch === "fix" ? qsTr("review and fix") : qsTr("review")) + engineNote)
                tone: review ? Style.gradeColor(review.grade) : Style.dim
                marked: true
                HoverHandler { cursorShape: verdict.review ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { enabled: verdict.review !== null; onTapped: detail.readRequested(verdict.review.file, qsTr("%1 · overwatch review").arg(detail.op.codename)) }
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
                // Reads in the app; the arrow opens it in the browser.
                Text {
                    visible: detail.op !== null && detail.op.handoffBrief.length > 0
                    text: qsTr("Handoff brief")
                    color: briefHover.hovered ? Style.text : theme.accent
                    font.family: Style.body
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    HoverHandler { id: briefHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: detail.readRequested(detail.op.handoffBrief, qsTr("%1 · handoff brief").arg(detail.op.codename)) }
                }
                Text {
                    visible: detail.op !== null && detail.op.handoffBrief.length > 0
                    text: "↗"
                    color: briefOutHover.hovered ? theme.accent : Style.dim
                    font.pixelSize: 13
                    ToolTip.visible: briefOutHover.hovered
                    ToolTip.text: qsTr("Open in the browser")
                    HoverHandler { id: briefOutHover; cursorShape: Qt.PointingHandCursor }
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
            // The comms tab shows this in its own "now" row.
            Text {
                Layout.fillWidth: true
                visible: detail.live && detail.tab !== 0
                text: "▸ " + (detail.op && detail.op.activity ? detail.op.activity : qsTr("Awaiting contact…"))
                elide: Text.ElideRight
                color: theme.accent
                font.family: Style.mono
                font.variableAxes: Style.narrow
                font.pixelSize: 12
            }
        }

        // The tabs: comms, brief, proof and history (Ctrl+1…4). The comms
        // filters and search sit at the right of the bar on the comms tab.
        Item {
            Layout.fillWidth: true
            implicitHeight: 32
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Style.line }
            RowLayout {
                anchors.fill: parent
                spacing: 18
                Row {
                    id: tabRow
                    Layout.fillHeight: true
                    spacing: 18
                    Repeater {
                        model: [qsTr("Comms"), qsTr("Brief"), qsTr("Proof"), qsTr("History")]
                        delegate: Item {
                            id: tabItem
                            required property string modelData
                            required property int index
                            readonly property bool chosen: detail.tab === index
                            // Proof carries the latest gates' state as a square.
                            readonly property var gates: index === 2 && detail.op ? detail.op.lastGates : []
                            implicitWidth: tabLabel.implicitWidth + (gates.length > 0 ? 13 : 0)
                            height: parent.height
                            Text {
                                id: tabLabel
                                anchors.verticalCenter: parent.verticalCenter
                                text: tabItem.modelData
                                color: tabItem.chosen ? Style.text : tabHover.hovered ? Style.text2 : Style.dim
                                font.family: Style.body
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }
                            Rectangle {
                                visible: tabItem.gates.length > 0
                                anchors.left: tabLabel.right
                                anchors.leftMargin: 7
                                anchors.verticalCenter: parent.verticalCenter
                                width: 6; height: 6
                                color: tabItem.gates.every(g => g.passed) ? Style.good : Style.danger
                            }
                            Rectangle {
                                visible: tabItem.chosen
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 2
                                color: theme.accent
                            }
                            HoverHandler { id: tabHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: detail.tab = tabItem.index }
                            ToolTip.visible: tabHover.hovered
                            ToolTip.delay: 600
                            ToolTip.text: qsTr("Ctrl+%1").arg(tabItem.index + 1)
                        }
                    }
                }
                Item { Layout.fillWidth: true; Layout.minimumWidth: 0 }
                // The filters give way (cut at the edge) before the panel widens.
                Item {
                    visible: detail.tab === 0
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: filters.implicitWidth
                    implicitHeight: 22
                    clip: true
                    Row {
                        id: filters
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
                    visible: detail.tab === 0
                    // It gives way first when the bar is narrow.
                    Layout.fillWidth: true
                    Layout.maximumWidth: 140
                    Layout.minimumWidth: 70
                    Layout.preferredHeight: 30
                    Layout.bottomMargin: 2
                    placeholderText: qsTr("Search  /")
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 12
                    topPadding: 4
                    bottomPadding: 4
                    Keys.onEscapePressed: { text = ""; detail.forceActiveFocus() }
                    onTextChanged: Qt.callLater(detail.refreshComms)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: -6
            spacing: 18

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: detail.tab

                // Comms: the agent's stream, newest at the bottom.
                Rectangle {
                    Layout.minimumHeight: detail.tight ? 80 : 120
                    color: Style.panel
                    border.color: Style.line
                    radius: theme.radius
                    ListView {
                        id: comms
                        anchors.fill: parent
                        anchors.margins: 12
                        anchors.bottomMargin: nowRow.visible ? nowRow.height + 8 : 12
                        clip: true
                        spacing: 6
                        model: commsRows
                        verticalLayoutDirection: ListView.BottomToTop
                        ScrollBar.vertical: ScrollBar {
                            id: commsBar
                            onPressedChanged: if (!pressed) comms.following = comms.nearEnd()
                        }
                        // Newest at the bottom, laid out from there, so new
                        // lines show while the view is at the end and leave
                        // it in place when the operator has scrolled back.
                        property bool following: true
                        property bool settling: false
                        function nearEnd() { return contentHeight <= height || contentY >= originY + contentHeight - height - 30 }
                        function follow() {
                            if (!following)
                                return
                            settling = true
                            positionViewAtBeginning()
                            settling = false
                        }
                        onContentYChanged: if (!settling && (moving || commsBar.pressed)) following = nearEnd()
                        onMovementEnded: following = nearEnd()
                        onCountChanged: Qt.callLater(follow)
                        onHeightChanged: Qt.callLater(follow)
                        Component.onCompleted: detail.refreshComms()
                        delegate: CommsLine {
                            id: row
                            required property int first
                            required time
                            required kind
                            required text
                            required count
                            required summary
                            width: ListView.view.width - 10
                            expanded: count > 1 && detail.expanded[detail.runKey(row)] === true
                            entries: expanded ? detail.runOf(first, count) : []
                            onToggled: {
                                const next = Object.assign({}, detail.expanded)
                                next[detail.runKey(row)] = !expanded
                                detail.expanded = next
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
                    // Scrolled back: a way down to the latest.
                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 30
                        anchors.bottom: comms.bottom
                        visible: !comms.following && comms.count > 0
                        implicitWidth: latestLabel.implicitWidth + 20
                        implicitHeight: 24
                        color: latestHover.hovered ? Style.raised : Style.bg
                        border.color: Style.lineStrong
                        radius: Math.min(2, theme.radius)
                        Text {
                            id: latestLabel
                            anchors.centerIn: parent
                            text: qsTr("Latest ↓")
                            color: Style.text2
                            font.family: Style.body
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }
                        HoverHandler { id: latestHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { comms.following = true; comms.follow() } }
                    }
                    // While deployed: what the agent is doing now.
                    Item {
                        id: nowRow
                        visible: detail.live
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 1
                        height: 32
                        Rectangle { width: parent.width; height: 1; color: Style.line }
                        Rectangle { anchors.fill: parent; anchors.topMargin: 1; color: Style.wash; opacity: 0.5 }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10
                            Rectangle {
                                id: pulse
                                property real glow: 1
                                implicitWidth: 7
                                implicitHeight: 7
                                color: theme.accent
                                opacity: Prefs.reduceMotion ? 1 : glow
                                SequentialAnimation on glow {
                                    running: nowRow.visible && !Prefs.reduceMotion
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.25; duration: 650; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 1; duration: 650; easing.type: Easing.InOutSine }
                                }
                            }
                            Text {
                                text: qsTr("Now")
                                color: theme.accent
                                font.family: Style.mono
                                font.variableAxes: Style.narrowMedium
                                font.pixelSize: 11
                            }
                            Text {
                                Layout.fillWidth: true
                                text: detail.op && detail.op.activity ? detail.op.activity : qsTr("Awaiting contact…")
                                elide: Text.ElideRight
                                color: Style.text
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 12
                                textFormat: Text.PlainText
                            }
                        }
                    }
                }

                // Brief: the objective, the latest sitrep and the acceptance criteria.
                Flickable {
                    id: briefPage
                    clip: true
                    contentWidth: width
                    contentHeight: briefColumn.implicitHeight + 16
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}
                    ColumnLayout {
                        id: briefColumn
                        width: briefPage.width - 14
                        y: 14
                        spacing: 8
                        SectionLabel { Layout.fillWidth: true; text: qsTr("Objective") }
                        Text {
                            Layout.fillWidth: true
                            Layout.maximumWidth: 720
                            text: detail.op ? detail.op.objective : ""
                            wrapMode: Text.Wrap
                            color: Style.text2
                            font.family: Style.body
                            font.pixelSize: 14
                            lineHeight: 1.35
                            textFormat: Text.PlainText
                        }
                        SectionLabel { Layout.fillWidth: true; Layout.topMargin: 12; text: qsTr("Sitrep") }
                        Text {
                            Layout.fillWidth: true
                            Layout.maximumWidth: 720
                            text: detail.op && detail.op.sitrep ? detail.op.sitrep : qsTr("No sitrep yet.")
                            wrapMode: Text.Wrap
                            color: detail.op && detail.op.sitrep ? Style.text2 : Style.faint
                            font.family: Style.body
                            font.pixelSize: 14
                            lineHeight: 1.35
                            textFormat: Text.PlainText
                        }
                        // Acceptance criteria: open, claimed by the agent, or
                        // ruled on by overwatch.
                        SectionLabel {
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            text: qsTr("Criteria")
                            detail: detail.op && detail.op.criteria.length > 0
                                    ? qsTr("%1 of %2 met").arg(detail.op.criteria.filter(c => c.state === "met").length).arg(detail.op.criteria.length) : ""
                        }
                        Repeater {
                            model: detail.op ? detail.op.criteria : []
                            delegate: CriterionRow { Layout.fillWidth: true; Layout.maximumWidth: 720 }
                        }
                        Text {
                            visible: !detail.op || detail.op.criteria.length === 0
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: qsTr("No acceptance criteria set. Amend the operation to add some.")
                            color: Style.faint
                            font.family: Style.body
                            font.pixelSize: 12
                        }
                    }
                }

                // Proof: the latest gates, the criteria and overwatch's verdict.
                Flickable {
                    id: proofPage
                    clip: true
                    contentWidth: width
                    contentHeight: proofColumn.implicitHeight + 16
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}
                    property int openGate: -1
                    readonly property var gates: detail.op ? detail.op.lastGates : []
                    readonly property var review: detail.op && detail.op.reviews.length > 0 ? detail.op.reviews[detail.op.reviews.length - 1] : null
                    ColumnLayout {
                        id: proofColumn
                        width: proofPage.width - 14
                        y: 14
                        spacing: 8
                        SectionLabel {
                            Layout.fillWidth: true
                            text: qsTr("Gates")
                            detail: proofPage.gates.length > 0
                                    ? qsTr("%1 of %2 passed").arg(proofPage.gates.filter(g => g.passed).length).arg(proofPage.gates.length) : ""
                        }
                        Repeater {
                            model: proofPage.gates
                            delegate: ColumnLayout {
                                id: gate
                                required property var modelData
                                required property int index
                                readonly property bool open: proofPage.openGate === index
                                Layout.fillWidth: true
                                spacing: 4
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: gateRow.implicitHeight + 12
                                    Rectangle {
                                        anchors.fill: parent
                                        color: gateHover.hovered ? Style.raised : Style.panel
                                        border.color: Style.line
                                        radius: Math.min(2, theme.radius)
                                    }
                                    RowLayout {
                                        id: gateRow
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        Rectangle {
                                            Layout.alignment: Qt.AlignTop
                                            Layout.topMargin: 5
                                            implicitWidth: 7; implicitHeight: 7
                                            color: gate.modelData.passed ? Style.good : Style.danger
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 10
                                                Text {
                                                    text: gate.modelData.name
                                                    color: Style.text
                                                    font.family: Style.body
                                                    font.pixelSize: 13
                                                    font.weight: Font.Medium
                                                }
                                                Text {
                                                    text: gate.modelData.passed ? qsTr("Passed") : qsTr("Failed")
                                                    color: gate.modelData.passed ? Style.good : Style.danger
                                                    font.family: Style.body
                                                    font.pixelSize: 12
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: gate.modelData.command
                                                    elide: Text.ElideMiddle
                                                    color: Style.dim
                                                    font.family: Style.mono
                                                    font.variableAxes: Style.narrow
                                                    font.pixelSize: 11
                                                }
                                                Text {
                                                    text: gate.modelData.seconds + "s"
                                                    color: Style.dim
                                                    font.family: Style.mono
                                                    font.variableAxes: Style.narrow
                                                    font.pixelSize: 11
                                                    font.features: { "tnum": 1 }
                                                }
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                visible: text.length > 0
                                                text: (gate.open ? "▾ " : "▸ ") + detail.gateSummary(gate.modelData.output)
                                                elide: Text.ElideRight
                                                color: Style.text2
                                                font.family: Style.mono
                                                font.variableAxes: Style.narrow
                                                font.pixelSize: 11
                                                textFormat: Text.PlainText
                                            }
                                        }
                                    }
                                    HoverHandler { id: gateHover; cursorShape: gate.modelData.output ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                    TapHandler {
                                        enabled: !!gate.modelData.output
                                        onTapped: proofPage.openGate = gate.open ? -1 : gate.index
                                    }
                                }
                                // The tail of the gate's output.
                                Rectangle {
                                    Layout.fillWidth: true
                                    visible: gate.open
                                    implicitHeight: tail.implicitHeight + 16
                                    color: Style.bg
                                    border.color: Style.line
                                    radius: Math.min(2, theme.radius)
                                    Text {
                                        id: tail
                                        x: 10; y: 8
                                        width: parent.width - 20
                                        text: gate.open ? detail.gateTail(gate.modelData.output) : ""
                                        wrapMode: Text.WrapAnywhere
                                        color: Style.text2
                                        font.family: Style.mono
                                        font.variableAxes: Style.narrow
                                        font.pixelSize: 11
                                        lineHeight: 1.15
                                        textFormat: Text.PlainText
                                    }
                                }
                            }
                        }
                        // None run yet: what's configured, or how to add some.
                        Repeater {
                            model: proofPage.gates.length === 0 && detail.op ? detail.op.gates : []
                            delegate: RowLayout {
                                id: planned
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 10
                                Rectangle { implicitWidth: 7; implicitHeight: 7; color: Style.faint }
                                Text {
                                    text: planned.modelData.name
                                    color: Style.text2
                                    font.family: Style.body
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: planned.modelData.command
                                    elide: Text.ElideMiddle
                                    color: Style.dim
                                    font.family: Style.mono
                                    font.variableAxes: Style.narrow
                                    font.pixelSize: 11
                                }
                            }
                        }
                        Text {
                            visible: proofPage.gates.length === 0
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: detail.op && detail.op.gates.length > 0 ? qsTr("The gates run after each cycle; none has run yet.")
                                                                          : qsTr("No gates set. Amend the operation to check each cycle with your tests.")
                            color: Style.faint
                            font.family: Style.body
                            font.pixelSize: 12
                        }

                        SectionLabel {
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            text: qsTr("Criteria")
                            detail: detail.op && detail.op.criteria.length > 0
                                    ? qsTr("%1 of %2 met").arg(detail.op.criteria.filter(c => c.state === "met").length).arg(detail.op.criteria.length) : ""
                        }
                        Repeater {
                            model: detail.op ? detail.op.criteria : []
                            delegate: CriterionRow { Layout.fillWidth: true; showEvidence: true }
                        }
                        Text {
                            visible: !detail.op || detail.op.criteria.length === 0
                            Layout.fillWidth: true
                            text: qsTr("No acceptance criteria set.")
                            color: Style.faint
                            font.family: Style.body
                            font.pixelSize: 12
                        }

                        SectionLabel {
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            text: qsTr("Overwatch")
                            detail: proofPage.review ? qsTr("cycle %1").arg(proofPage.review.cycle) : ""
                        }
                        Text {
                            visible: detail.reviewOn.length > 0 && detail.op !== null && detail.op.overwatch !== "off"
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: detail.reviewEngine.length > 0 ? qsTr("Reviews on %1, not the operation's own engine.").arg(detail.reviewOn)
                                                                 : qsTr("Reviews with the %1 model.").arg(detail.reviewModel)
                            color: Style.dim
                            font.family: Style.body
                            font.pixelSize: 12
                        }
                        RowLayout {
                            visible: proofPage.review !== null
                            Layout.fillWidth: true
                            spacing: 12
                            Chip {
                                text: proofPage.review ? Style.gradeLabel(proofPage.review.grade) : ""
                                tone: proofPage.review ? Style.gradeColor(proofPage.review.grade) : Style.dim
                                marked: true
                            }
                            Text {
                                text: qsTr("Read the review")
                                color: reviewHover.hovered ? Style.text : theme.accent
                                font.family: Style.body
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                HoverHandler { id: reviewHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    onTapped: detail.readRequested(proofPage.review.file,
                                                                   qsTr("%1 · overwatch review, cycle %2").arg(detail.op.codename).arg(proofPage.review.cycle))
                                }
                            }
                            Text {
                                text: "↗"
                                color: reviewOutHover.hovered ? theme.accent : Style.dim
                                font.pixelSize: 13
                                ToolTip.visible: reviewOutHover.hovered
                                ToolTip.text: qsTr("Open in the browser")
                                HoverHandler { id: reviewOutHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: ops.openReport(proofPage.review.file) }
                            }
                            Item { Layout.fillWidth: true }
                        }
                        Text {
                            visible: proofPage.review !== null && !!proofPage.review.summary
                            Layout.fillWidth: true
                            Layout.maximumWidth: 720
                            text: proofPage.review ? proofPage.review.summary || "" : ""
                            wrapMode: Text.Wrap
                            color: Style.text2
                            font.family: Style.body
                            font.pixelSize: 13
                            lineHeight: 1.3
                            textFormat: Text.PlainText
                        }
                        Repeater {
                            model: proofPage.review && proofPage.review.findings ? proofPage.review.findings : []
                            delegate: RowLayout {
                                id: finding
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.maximumWidth: 720
                                spacing: 10
                                Text {
                                    Layout.alignment: Qt.AlignTop
                                    Layout.preferredWidth: 52
                                    text: finding.modelData.severity || ""
                                    color: finding.modelData.severity === "high" ? Style.danger
                                         : finding.modelData.severity === "medium" ? Style.amber : Style.dim
                                    font.family: Style.mono
                                    font.variableAxes: Style.narrowMedium
                                    font.pixelSize: 11
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: (finding.modelData.file ? "<font color=\"" + Style.dim + "\">" + finding.modelData.file + "</font>  " : "")
                                          + String(finding.modelData.issue || "").replace(/&/g, "&amp;").replace(/</g, "&lt;")
                                    textFormat: Text.StyledText
                                    wrapMode: Text.Wrap
                                    color: Style.text2
                                    font.family: Style.body
                                    font.pixelSize: 12
                                    lineHeight: 1.25
                                }
                            }
                        }
                        Text {
                            visible: proofPage.review === null
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: detail.op && detail.op.overwatch !== "off" ? qsTr("Overwatch reviews the work when the operation completes.")
                                                                             : qsTr("Overwatch is off for this operation.")
                            color: Style.faint
                            font.family: Style.body
                            font.pixelSize: 12
                        }
                    }
                }

                // History: the debriefs, the changed files and every cycle run.
                Flickable {
                    id: historyPage
                    clip: true
                    contentWidth: width
                    contentHeight: historyColumn.implicitHeight + 16
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}
                    readonly property var runs: detail.op ? detail.op.history : []
                    ColumnLayout {
                        id: historyColumn
                        width: historyPage.width - 14
                        y: 14
                        spacing: 8
                        SectionLabel {
                            Layout.fillWidth: true
                            text: qsTr("Debriefs")
                            detail: detail.op ? "" + detail.op.reports.length : ""
                        }
                        Repeater {
                            model: detail.op ? detail.op.reports.slice().reverse() : []
                            delegate: DebriefRow { Layout.fillWidth: true }
                        }
                        Text {
                            visible: !detail.op || detail.op.reports.length === 0
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: qsTr("Debriefs land here as each cycle completes.")
                            color: Style.faint
                            font.family: Style.body
                            font.pixelSize: 12
                        }

                        SectionLabel {
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            text: qsTr("Cycle runs")
                            detail: historyPage.runs.length === 0 ? ""
                                : qsTr("%1 · ≈$%2").arg(detail.duration(historyPage.runs.reduce((t, r) => t + Number(r.seconds || 0), 0)))
                                      .arg(historyPage.runs.reduce((t, r) => t + Number(r.cost || 0), 0).toLocaleString(Qt.locale(), 'f', 2))
                        }
                        Rectangle {
                            visible: historyPage.runs.length > 0
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: Style.lineStrong
                        }
                        Repeater {
                            model: historyPage.runs
                            delegate: Item {
                                id: run
                                required property var modelData
                                required property int index
                                readonly property color tone: modelData.outcome === "complete" ? theme.accent
                                                            : modelData.outcome === "cut" ? Style.amber : Style.danger
                                Layout.fillWidth: true
                                implicitHeight: 30
                                Rectangle { anchors.fill: parent; color: runHover.hovered ? Style.raised : "transparent" }
                                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Style.line }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 12
                                    Rectangle { implicitWidth: 6; implicitHeight: 6; color: run.tone }
                                    Text {
                                        Layout.preferredWidth: 40
                                        text: qsTr("C%1").arg(Style.pad(run.modelData.cycle))
                                        color: Style.text
                                        font.family: Style.mono
                                        font.variableAxes: Style.wide
                                        font.pixelSize: 12
                                        font.features: { "tnum": 1 }
                                    }
                                    Text {
                                        Layout.preferredWidth: 90
                                        text: run.modelData.outcome === "complete" ? Style.statusLabel("complete")
                                            : run.modelData.outcome === "cut" ? qsTr("Cut short")
                                            : run.modelData.outcome === "aborted" ? qsTr("Aborted") : qsTr("Failed")
                                        elide: Text.ElideRight
                                        color: run.modelData.outcome === "complete" ? Style.text2 : run.tone
                                        font.family: Style.body
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: run.modelData.before ? qsTr("%n file(s)", "", run.modelData.files)
                                                                     + qsTr(" · <font color=\"%1\">+%2</font> <font color=\"%3\">−%4</font>")
                                                                         .arg(theme.accent).arg(run.modelData.added)
                                                                         .arg(Style.dim).arg(run.modelData.removed)
                                                                   : qsTr("No git intel")
                                        textFormat: Text.StyledText
                                        elide: Text.ElideRight
                                        color: Style.text2
                                        font.family: Style.mono
                                        font.variableAxes: Style.narrow
                                        font.pixelSize: 11
                                        font.features: { "tnum": 1 }
                                    }
                                    Text {
                                        text: detail.duration(Number(run.modelData.seconds || 0))
                                        horizontalAlignment: Text.AlignRight
                                        Layout.preferredWidth: 64
                                        color: Style.dim
                                        font.family: Style.mono
                                        font.variableAxes: Style.narrow
                                        font.pixelSize: 11
                                        font.features: { "tnum": 1 }
                                    }
                                    Text {
                                        text: "≈$" + Number(run.modelData.cost || 0).toLocaleString(Qt.locale(), 'f', 2)
                                        horizontalAlignment: Text.AlignRight
                                        Layout.preferredWidth: 56
                                        color: Style.text2
                                        font.family: Style.mono
                                        font.variableAxes: Style.narrow
                                        font.pixelSize: 11
                                        font.features: { "tnum": 1 }
                                    }
                                }
                                HoverHandler { id: runHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: detail.diffRequested(run.index) }
                            }
                        }
                        Text {
                            visible: historyPage.runs.length === 0
                            Layout.fillWidth: true
                            text: qsTr("No cycle has run yet.")
                            color: Style.faint
                            font.family: Style.body
                            font.pixelSize: 12
                        }

                        SectionLabel {
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            text: qsTr("Intel")
                            detail: detail.op && detail.op.intel.length ? qsTr("%1 changed").arg(detail.op.intel.length) : ""
                        }
                        Repeater {
                            model: detail.op ? detail.op.intel : []
                            delegate: Text {
                                required property string modelData
                                Layout.fillWidth: true
                                text: modelData
                                elide: Text.ElideMiddle
                                color: modelData.startsWith("??") || modelData.startsWith("A") ? Style.text : modelData.startsWith(" D") || modelData.startsWith("D") ? Style.danger : Style.text2
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 11
                            }
                        }
                        Text {
                            visible: !detail.op || detail.op.intel.length === 0
                            text: qsTr("No changed files reported by git.")
                            color: Style.faint
                            font.family: Style.body
                            font.pixelSize: 12
                        }
                    }
                }
            }

            // Wide: the objective and sitrep stay beside the comms.
            ColumnLayout {
                readonly property int sideWidth: Math.round(Math.min(380, detail.width * 0.3))
                visible: detail.wide && detail.tab === 0
                Layout.preferredWidth: sideWidth
                Layout.maximumWidth: sideWidth
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                clip: true
                spacing: 8

                SectionLabel { Layout.fillWidth: true; text: qsTr("Objective") }
                Text {
                    id: objectiveText
                    Layout.fillWidth: true
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    text: detail.op ? detail.op.objective : ""
                    wrapMode: Text.Wrap
                    color: Style.text2
                    font.family: Style.body
                    font.pixelSize: 14
                    lineHeight: 1.3
                    textFormat: Text.PlainText
                }
                SectionLabel { Layout.fillWidth: true; Layout.topMargin: 8; text: qsTr("Sitrep") }
                Text {
                    id: sitrepText
                    Layout.fillWidth: true
                    maximumLineCount: 5
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
                    Layout.topMargin: 8
                    visible: detail.op !== null && detail.op.reports.length > 0
                    text: qsTr("Debriefs")
                    detail: detail.op ? "" + detail.op.reports.length : ""
                }
                ListView {
                    id: debriefs
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, 150)
                    clip: true
                    interactive: contentHeight > height
                    model: detail.op ? detail.op.reports.slice().reverse() : []
                    delegate: DebriefRow { width: ListView.view.width }
                }
                Item { Layout.fillHeight: true }
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
