import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Shapes

// Campaigns: a large objective planned into operations with dependencies,
// reviewed and edited here as a graph, then run in order.
Item {
    id: board
    visible: false
    // The campaign shown, by id, or "" for a new one.
    property string current: ""
    property bool creating: false
    // The plan card being edited, by key.
    property string editing: ""
    property bool picking: false
    readonly property var campaign: {
        for (const c of ops.campaigns)
            if (c.id === current)
                return c
        return null
    }
    readonly property bool draft: campaign !== null && campaign.status === "draft"
    // A budget can be set while the campaign is up for review or running.
    readonly property bool budgetable: campaign !== null && (campaign.status === "draft" || campaign.status === "active")
    // What the campaign has spent: its planning plus its operations' API value.
    readonly property real spent: {
        if (!campaign)
            return 0
        const members = campaign.operations.map(o => o.opId).filter(id => id !== undefined)
        let total = Number(campaign.cost || 0)
        for (let i = 0; i < campaignSpend.count; ++i) {
            const item = campaignSpend.itemAt(i)
            if (item && members.indexOf(item.opId) >= 0)
                total += item.cost
        }
        return total
    }
    function money(value) { return "$" + Number(value).toLocaleString(Qt.locale(), 'f', 2) }
    function applyBudget() {
        if (!campaign)
            return
        const value = Number.fromLocaleString(Qt.locale(), budgetField.text.length > 0 ? budgetField.text : "0")
        if (isNaN(value) || value < 0)
            return
        const usd = Math.round(value * 100) / 100
        if (usd !== Number(campaign.budget || 0))
            ops.setCampaignBudget(current, usd)
    }
    // The field shows the campaign's budget whenever the campaign changes.
    onCampaignChanged: if (!budgetField.activeFocus)
        budgetField.text = campaign && campaign.budget > 0 ? Number(campaign.budget).toFixed(2) : ""

    // Each operation's spend, read live.
    Repeater {
        id: campaignSpend
        model: ops
        delegate: Item {
            required property string opId
            required property double cost
        }
    }

    // Each operation's record (runs, comms, when it was made), by id, for the timeline.
    Repeater {
        id: opRecords
        model: ops
        delegate: Item {
            required property string opId
            required property var history
            required property var comms
            required property var created
            required property string status
            required property string codename
            required property double cost
        }
    }
    readonly property var records: {
        const result = {}
        for (let i = 0; i < opRecords.count; ++i) {
            const item = opRecords.itemAt(i)
            if (item)
                result[item.opId] = { history: item.history || [], comms: item.comms || [], created: item.created,
                                      status: item.status, codename: item.codename, cost: item.cost }
        }
        return result
    }

    // "graph" or "timeline"; Ctrl+T or the toggle over the frame swaps them.
    property string view: "graph"
    readonly property bool canToggle: campaign !== null && campaign.status !== "planning" && campaign.operations.length > 0
    readonly property bool showTimeline: canToggle && view === "timeline"
    // The clock the timeline's live end follows.
    property real now: Date.now()
    Timer {
        interval: 1000
        repeat: true
        running: board.visible && board.showTimeline && board.timeline.live
        onTriggered: board.now = Date.now()
    }
    onShowTimelineChanged: { now = Date.now(); tip.target = null }

    function when(value) {
        if (value instanceof Date)
            return value.getTime()
        if (value === undefined || value === null || value === "")
            return NaN
        return Date.parse(value)
    }
    function duration(seconds) {
        const s = Math.max(0, Math.round(seconds))
        if (s < 60)
            return qsTr("%1s").arg(s)
        if (s < 3600)
            return qsTr("%1m").arg(Math.round(s / 60))
        return qsTr("%1h %2m").arg(Math.floor(s / 3600)).arg(Math.floor((s % 3600) / 60))
    }
    function showTip(on, item, text) {
        if (on) {
            tip.target = item
            tip.text = text
        } else if (tip.target === item) {
            tip.target = null
        }
    }
    function outcomeColor(outcome) {
        return outcome === "complete" ? theme.accent
             : outcome === "failed" || outcome === "aborted" ? Style.danger
             : outcome === "cut" || outcome === "pinned" || outcome === "interrupted" || outcome === "held" ? Style.amber
             : Style.dim
    }
    function outcomeLabel(outcome) {
        switch (outcome) {
        case "complete": return qsTr("complete")
        case "failed": return qsTr("failed")
        case "aborted": return qsTr("aborted")
        case "cut": return qsTr("cut")
        case "pinned": return qsTr("pinned")
        case "live": return qsTr("in progress")
        }
        return outcome
    }

    // The campaign laid out in time: one lane per operation, ordered by
    // dependency depth then start. Its live ends are -1, meaning "now", so the
    // clock moves them without rebuilding the lanes.
    readonly property var timeline: {
        const result = { lanes: [], merges: [], start: NaN, end: NaN, started: false, live: false }
        if (!campaign)
            return result
        result.live = campaign.status === "active" || campaign.status === "blocked"
        const operations = campaign.operations
        const byKey = {}
        for (const op of operations)
            byKey[op.key] = op
        const depth = {}
        const depthOf = (key, seen) => {
            if (depth[key] !== undefined) return depth[key]
            if (seen.indexOf(key) >= 0 || !byKey[key]) return 0
            const deps = byKey[key].depends.filter(d => byKey[d])
            const d = deps.length === 0 ? 0 : 1 + Math.max(...deps.map(k => depthOf(k, seen.concat([key]))))
            depth[key] = d
            return d
        }
        let start = Infinity, end = -Infinity
        const lanes = operations.map((op, order) => {
            const record = op.opId ? records[op.opId] : undefined
            const lane = { op: op, order: order, depth: depthOf(op.key, []), runs: [], merges: [], liveRun: null,
                           created: NaN, first: NaN, total: 0, wait: null,
                           waitingOn: op.depends.filter(d => byKey[d]).map(d => byKey[d].codename || d) }
            if (!record)
                return lane
            lane.created = when(record.created)
            let spent = 0
            for (const entry of record.history) {
                const at = when(entry.started)
                if (isNaN(at))
                    continue
                const seconds = Math.max(0, Number(entry.seconds || 0))
                lane.runs.push({ start: at, end: at + seconds * 1000, seconds: seconds, cycle: entry.cycle,
                                 cost: Number(entry.cost || 0), outcome: entry.outcome || "" })
                spent += Number(entry.cost || 0)
                lane.total += seconds
            }
            for (const line of record.comms)
                if (line && line.at && String(line.text || "").indexOf("Extracted") >= 0)
                    lane.merges.push(Number(line.at))
            const lastEnd = lane.runs.reduce((m, r) => Math.max(m, r.end), -Infinity)
            if (record.status === "deployed") {
                // The run under way: from its "deployed" line, else the last run's end.
                let begun = NaN
                for (const line of record.comms)
                    if (line && line.at && line.kind === "sys" && String(line.text || "").indexOf("deployed") >= 0
                            && Number(line.at) >= (isFinite(lastEnd) ? lastEnd - 1000 : 0))
                        begun = Number(line.at)
                if (isNaN(begun))
                    begun = isFinite(lastEnd) ? lastEnd : lane.created
                if (!isNaN(begun))
                    lane.liveRun = { start: begun, end: -1, cycle: (op.cyclesDone || 0) + 1,
                                     cost: Math.max(0, Number(record.cost || 0) - spent), outcome: "live" }
            }
            const starts = lane.runs.map(r => r.start).concat(lane.liveRun ? [lane.liveRun.start] : [])
            lane.first = starts.length > 0 ? Math.min(...starts) : NaN
            for (const t of [lane.created, lane.first])
                if (!isNaN(t)) start = Math.min(start, t)
            for (const t of lane.runs.map(r => r.end).concat(lane.merges))
                end = Math.max(end, t)
            return lane
        })
        result.started = isFinite(start)
        if (result.started) {
            result.start = start
            result.end = Math.max(end, start)
            for (const lane of lanes) {
                // Waiting: from being made until the first run, or until now.
                const until = !isNaN(lane.first) ? lane.first
                            : result.live && lane.op.status !== "complete" && lane.op.status !== "failed" ? -1 : NaN
                const from = isNaN(lane.created) ? start : lane.created
                lane.wait = isNaN(until) || (until !== -1 && until - from < 1000) ? null : { start: from, end: until }
                for (const at of lane.merges)
                    result.merges.push({ at: at, codename: lane.op.codename || lane.op.key })
            }
        }
        lanes.sort((a, b) => a.depth - b.depth
                   || (isNaN(a.first) ? Infinity : a.first) - (isNaN(b.first) ? Infinity : b.first)
                   || a.order - b.order)
        result.lanes = lanes
        return result
    }

    signal operationPicked(int row)

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius
    Material.background: Style.panel

    function open() {
        creating = ops.campaigns.length === 0
        if (!creating && (current === "" || campaign === null))
            current = ops.campaigns[0].id
        editing = ""
        visible = true
        enter.restart()
        if (creating)
            nameField.forceActiveFocus()
    }
    function close() { commitEditor(); visible = false }
    function startNew() {
        creating = true
        editing = ""
        nameField.text = ops.suggestCodename()
        objectiveField.text = ""
        error.text = ""
        nameField.forceActiveFocus()
    }
    function plan() {
        const problem = ops.validate(directoryField.text, objectiveField.text)
        if (problem.length > 0) {
            error.text = problem
            return
        }
        const id = ops.planCampaign(nameField.text, directoryField.text, objectiveField.text,
                                    plannerModel.currentIndex === 0 ? "" : plannerModel.currentText)
        if (id.length > 0) {
            current = id
            creating = false
        }
    }
    // Plan edits go back as a whole list.
    function planWith(key, changes) {
        const next = campaign.operations.map(op => {
            const copy = { key: op.key, codename: op.codename, objective: op.objective, cycles: op.cycles,
                           model: op.model, depends: op.depends.slice() }
            return op.key === key ? Object.assign(copy, changes) : copy
        })
        return ops.updateCampaignPlan(current, next)
    }
    function removeFromPlan(key) {
        const next = campaign.operations.filter(op => op.key !== key).map(op => ({
            key: op.key, codename: op.codename, objective: op.objective, cycles: op.cycles, model: op.model,
            depends: op.depends.filter(d => d !== key) }))
        if (ops.updateCampaignPlan(current, next))
            editing = ""
    }
    function addToPlan() {
        let n = campaign.operations.length + 1
        while (campaign.operations.some(op => op.key === "op-" + n))
            n++
        const next = campaign.operations.map(op => ({ key: op.key, codename: op.codename, objective: op.objective,
                                                     cycles: op.cycles, model: op.model, depends: op.depends.slice() }))
        next.push({ key: "op-" + n, codename: ops.suggestCodename(), objective: qsTr("Describe what this operation delivers."),
                    cycles: 2, model: "sonnet", depends: [] })
        if (ops.updateCampaignPlan(current, next))
            editing = "op-" + n
    }
    // The editor's fields save on Enter or losing focus; a click on a button
    // takes neither, so approving or switching cards saves them first.
    function commitEditor() {
        if (!draft || editing === "" || !editor.op)
            return
        const changes = {}
        if (editCodename.text.trim().length > 0 && editCodename.text.toUpperCase() !== editor.op.codename)
            changes.codename = editCodename.text.toUpperCase()
        if (editObjective.text.trim().length > 0 && editObjective.text !== editor.op.objective)
            changes.objective = editObjective.text
        if (Object.keys(changes).length > 0)
            planWith(editing, changes)
    }
    function approve() {
        commitEditor()
        ops.approveCampaign(current, campaignRoe.keys[campaignRoe.currentIndex],
                            campaignOverwatch.keys[campaignOverwatch.currentIndex])
    }
    function statusColor(status) {
        return status === "complete" ? Style.good : status === "active" ? theme.accent
             : status === "blocked" || status === "failed" ? Style.danger
             : status === "planning" ? Style.amber : Style.dim
    }
    function statusLabel(status) {
        switch (status) {
        case "planning": return qsTr("Planning")
        case "draft": return qsTr("Ready for review")
        case "active": return qsTr("Active")
        case "blocked": return qsTr("Blocked")
        case "complete": return qsTr("Complete")
        case "failed": return qsTr("Planning failed")
        }
        return status
    }

    // Canvas wants CSS colours; tokens may carry alpha.
    function css(value, alpha) {
        const c = Qt.lighter(value, 1.0)
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + ","
             + (alpha === undefined ? c.a : alpha) + ")"
    }
    readonly property bool narrow: sheet.width < 980

    Connections {
        target: folderPicker
        function onPicked(path) { if (board.picking) { directoryField.text = path; board.picking = false } }
        function onFailed(message) { if (board.picking) { error.text = message; board.picking = false } }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Style.bg.r, Style.bg.g, Style.bg.b, 0.86)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: board.close() }
    }

    Rectangle {
        id: sheet
        property real rise: 0
        anchors.centerIn: parent
        anchors.verticalCenterOffset: rise
        width: parent.width - 48
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
            NumberAnimation { target: sheet; property: "rise"; from: 8; to: 0; duration: 180; easing.type: Easing.OutCubic }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: board.narrow ? 20 : 28
            spacing: board.narrow ? 16 : 24

            // Every campaign, newest first.
            ColumnLayout {
                Layout.preferredWidth: board.narrow ? 196 : 264
                Layout.minimumWidth: board.narrow ? 196 : 264
                Layout.maximumWidth: board.narrow ? 196 : 264
                Layout.fillHeight: true
                spacing: 14
                ColumnLayout {
                    spacing: 4
                    Text {
                        Layout.fillWidth: true
                        text: "# " + qsTr("Command // theatre").toLowerCase()
                        elide: Text.ElideRight
                        color: Style.dim
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                        font.pixelSize: 11
                    }
                    Text {
                        text: qsTr("Campaigns")
                        color: Style.text
                        font.family: Style.display
                        font.pixelSize: 28
                        font.weight: Font.DemiBold
                        font.letterSpacing: -0.6
                    }
                }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }
                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: ops.campaigns
                    delegate: Item {
                        id: entry
                        required property var modelData
                        readonly property bool chosen: !board.creating && board.current === modelData.id
                        readonly property int done: modelData.operations.filter(o => o.status === "complete").length
                        width: ListView.view.width
                        height: 72
                        // Selected: a wash, a leading rule and corner marks; hover lifts a step.
                        Rectangle {
                            anchors.fill: parent
                            color: entry.chosen ? Style.wash : entryHover.hovered ? Style.raised : "transparent"
                            Rectangle { visible: entry.chosen; width: 2; height: parent.height; color: theme.accent }
                            Brackets { anchors.fill: parent; visible: entry.chosen; size: 7 }
                        }
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 12
                            anchors.topMargin: 11
                            anchors.bottomMargin: 11
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 9
                                Rectangle { implicitWidth: 7; implicitHeight: 7; color: board.statusColor(entry.modelData.status) }
                                Text {
                                    Layout.fillWidth: true
                                    text: entry.modelData.name
                                    elide: Text.ElideRight
                                    color: entry.chosen ? Style.text : Style.text2
                                    font.family: Style.mono
                                    font.variableAxes: Style.wide
                                    font.pixelSize: 14
                                    font.letterSpacing: -0.3
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: board.statusLabel(entry.modelData.status) + " · "
                                      + qsTr("%n operation(s)", "", entry.modelData.operations.length)
                                elide: Text.ElideRight
                                color: Style.dim
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 11
                            }
                            // One cell per operation, filled as each completes.
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 2
                                spacing: 3
                                Repeater {
                                    model: entry.modelData.operations.length
                                    delegate: Rectangle {
                                        required property int index
                                        Layout.fillWidth: true
                                        implicitHeight: 2
                                        color: index < entry.done ? theme.accent : Style.line
                                    }
                                }
                            }
                        }
                        HoverHandler { id: entryHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { board.current = entry.modelData.id; board.creating = false; board.editing = "" } }
                    }
                }
                TacticalButton {
                    Layout.fillWidth: true
                    text: qsTr("New campaign")
                    primary: board.creating
                    onClicked: board.startNew()
                }
            }

            Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Style.line }

            // A new campaign: the objective and where.
            ColumnLayout {
                visible: board.creating
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 14
                SectionLabel { Layout.fillWidth: true; text: qsTr("Plan a campaign") }
                Text {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 720
                    text: qsTr("Give the whole objective. A planner (read-only, it changes nothing) surveys the project and breaks it into operations with dependencies, for you to review before anything runs.")
                    wrapMode: Text.Wrap
                    color: Style.text2
                    font.family: Style.body
                    font.pixelSize: 13
                    lineHeight: 1.15
                }
                TextField {
                    id: nameField
                    Layout.fillWidth: true
                    placeholderText: qsTr("Campaign name")
                    font.family: Style.mono
                    font.variableAxes: Style.wide
                    // A callsign, so it's typed in capitals; the field's own
                    // label stays in sentence case.
                    onTextEdited: { const at = cursorPosition; const upper = text.toUpperCase(); if (upper !== text) { text = upper; cursorPosition = at } }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    TextField {
                        id: directoryField
                        Layout.fillWidth: true
                        placeholderText: qsTr("Project directory")
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                    }
                    TacticalButton {
                        text: folderPicker.busy ? qsTr("Waiting…") : qsTr("Browse")
                        enabled: !folderPicker.busy
                        onClicked: { board.picking = true; folderPicker.pick(qsTr("Choose the project directory")) }
                    }
                }
                ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 180
                    TextArea {
                        id: objectiveField
                        placeholderText: qsTr("The campaign objective, e.g. Build a habit tracker with a REST API, a web UI, and sync between devices.")
                        wrapMode: TextArea.Wrap
                        font.family: Style.body
                        font.pixelSize: 14
                    }
                }
                RowLayout {
                    spacing: 12
                    Text {
                        text: qsTr("Planner")
                        color: Style.text2
                        font.family: Style.body
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    ComboBox {
                        id: plannerModel
                        Layout.preferredWidth: 200
                        font.family: Style.body
                        model: [qsTr("Account default"), "opus", "sonnet", "haiku"]
                    }
                }
                Text {
                    id: error
                    Layout.fillWidth: true
                    visible: text.length > 0
                    wrapMode: Text.Wrap
                    color: Style.danger
                    font.family: Style.body
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                Item { Layout.fillHeight: true }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }
                RowLayout {
                    Layout.fillWidth: true
                    TacticalButton { text: qsTr("Close"); key: "Esc"; onClicked: board.close() }
                    Item { Layout.fillWidth: true }
                    TacticalButton { text: qsTr("Plan campaign"); key: "Ctrl+Enter"; primary: true; onClicked: board.plan() }
                }
            }

            // The campaign: its plan as a graph, live once it runs.
            ColumnLayout {
                visible: !board.creating && board.campaign !== null
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Rectangle {
                                implicitWidth: 7; implicitHeight: 7
                                color: board.campaign ? board.statusColor(board.campaign.status) : Style.dim
                            }
                            Text {
                                Layout.fillWidth: true
                                text: board.campaign ? board.statusLabel(board.campaign.status) + "  ·  " + board.campaign.directory : ""
                                color: Style.text2
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 11
                                elide: Text.ElideMiddle
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: board.campaign ? board.campaign.name : ""
                            elide: Text.ElideRight
                            color: Style.text
                            font.family: Style.mono
                            font.variableAxes: Style.wide
                            font.pixelSize: board.narrow ? 24 : 32
                            font.letterSpacing: -0.8
                        }
                    }
                    ColumnLayout {
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: 6
                        spacing: 4
                        // Spend against the campaign's budget, when it has one.
                        Text {
                            id: budgetLine
                            readonly property real share: board.campaign && board.campaign.budget > 0 ? board.spent / board.campaign.budget : 0
                            Layout.alignment: Qt.AlignRight
                            visible: board.campaign !== null && board.campaign.budget > 0
                            text: board.campaign ? qsTr("≈%1 of %2").arg(board.money(board.spent)).arg(board.money(board.campaign.budget)) : ""
                            color: share >= 1 ? Style.danger : share >= 0.8 ? Style.amber : Style.text
                            font.family: Style.mono
                            font.variableAxes: Style.narrow
                            font.pixelSize: 13
                            font.features: { "tnum": 1 }
                        }
                        Item {
                            Layout.alignment: Qt.AlignRight
                            visible: budgetLine.visible
                            implicitWidth: Math.max(96, budgetLine.implicitWidth)
                            implicitHeight: 2
                            Rectangle { anchors.fill: parent; color: Style.line }
                            Rectangle {
                                width: parent.width * Math.min(1, budgetLine.share)
                                height: parent.height
                                color: budgetLine.color === Style.text ? theme.accent : budgetLine.color
                            }
                        }
                        Text {
                            Layout.alignment: Qt.AlignRight
                            visible: board.campaign !== null && board.campaign.cost > 0
                            text: board.campaign ? "# " + qsTr("Planning ≈ $%1").arg(Number(board.campaign.cost).toLocaleString(Qt.locale(), 'f', 2)) : ""
                            color: Style.dim
                            font.family: Style.mono
                            font.variableAxes: Style.narrow
                            font.pixelSize: 11
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: board.campaign ? board.campaign.objective : ""
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    color: Style.text2
                    font.family: Style.body
                    font.pixelSize: 14
                    lineHeight: 1.15
                    textFormat: Text.PlainText
                }
                Text {
                    Layout.fillWidth: true
                    visible: board.campaign !== null && (board.campaign.summary.length > 0 || board.campaign.error.length > 0)
                    text: !board.campaign ? "" : board.campaign.error.length > 0 ? "⚠ " + board.campaign.error : board.campaign.summary
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    color: board.campaign && board.campaign.error.length > 0 ? Style.danger : Style.dim
                    font.family: Style.body
                    font.pixelSize: 13
                    lineHeight: 1.15
                    textFormat: Text.PlainText
                }

                // Over the frame: the timeline's key on the left, the view toggle on the right.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    visible: board.canToggle
                    spacing: 14
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: legend.implicitHeight
                        clip: true
                        Row {
                            id: legend
                            anchors.verticalCenter: parent.verticalCenter
                            visible: board.showTimeline && board.timeline.started
                            spacing: 14
                            Repeater {
                                model: [
                                    { tone: theme.accent, label: qsTr("Complete") },
                                    { tone: Style.danger, label: qsTr("Failed") },
                                    { tone: Style.amber, label: qsTr("Cut or pinned") }
                                ]
                                delegate: Row {
                                    required property var modelData
                                    spacing: 6
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 10; height: 6
                                        color: parent.modelData.tone
                                    }
                                    Text {
                                        text: parent.modelData.label
                                        color: Style.dim
                                        font.family: Style.body
                                        font.pixelSize: 12
                                    }
                                }
                            }
                            Row {
                                spacing: 6
                                Shape {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 14; height: 1
                                    ShapePath {
                                        strokeColor: Style.dim
                                        strokeWidth: 1
                                        strokeStyle: ShapePath.DashLine
                                        dashPattern: [2, 2]
                                        fillColor: "transparent"
                                        startX: 0; startY: 0.5
                                        PathLine { x: 14; y: 0.5 }
                                    }
                                }
                                Text {
                                    text: qsTr("Waiting")
                                    color: Style.dim
                                    font.family: Style.body
                                    font.pixelSize: 12
                                }
                            }
                            Row {
                                spacing: 6
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "◆"
                                    color: Style.good
                                    font.family: Style.mono
                                    font.pixelSize: 9
                                }
                                Text {
                                    text: qsTr("Merged")
                                    color: Style.dim
                                    font.family: Style.body
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                    KeyHint { key: "Ctrl+T"; label: "" ; spacing: 0 }
                    // Segmented: the current view washed and underlined.
                    Rectangle {
                        implicitWidth: segments.implicitWidth + 2
                        implicitHeight: 26
                        color: "transparent"
                        border.color: Style.lineStrong
                        radius: Math.min(2, theme.radius)
                        Row {
                            id: segments
                            anchors.fill: parent
                            anchors.margins: 1
                            Repeater {
                                model: [{ key: "graph", label: qsTr("Graph") }, { key: "timeline", label: qsTr("Timeline") }]
                                delegate: Rectangle {
                                    id: segment
                                    required property var modelData
                                    required property int index
                                    readonly property bool current: board.view === modelData.key
                                    width: segmentText.implicitWidth + 24
                                    height: parent.height
                                    color: current ? Style.wash : segmentHover.hovered ? Style.raised : "transparent"
                                    Rectangle {
                                        visible: segment.index > 0
                                        width: 1; height: parent.height
                                        color: Style.lineStrong
                                    }
                                    Text {
                                        id: segmentText
                                        anchors.centerIn: parent
                                        text: segment.modelData.label
                                        color: segment.current ? Style.text : Style.dim
                                        font.family: Style.body
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                    }
                                    Rectangle {
                                        visible: segment.current
                                        anchors.bottom: parent.bottom
                                        width: parent.width; height: 2
                                        color: theme.accent
                                    }
                                    HoverHandler { id: segmentHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: board.view = segment.modelData.key }
                                }
                            }
                        }
                    }
                }

                // The graph: one column per depth, supply lines between.
                Rectangle {
                    id: graphFrame
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.topMargin: 4
                    color: Style.bg
                    border.color: Style.line
                    radius: theme.radius
                    clip: true

                    readonly property var layout: {
                        const result = {}
                        if (!board.campaign)
                            return result
                        const operations = board.campaign.operations
                        const byKey = {}
                        for (const op of operations)
                            byKey[op.key] = op
                        const depth = {}
                        const depthOf = (key, seen) => {
                            if (depth[key] !== undefined) return depth[key]
                            if (seen.indexOf(key) >= 0 || !byKey[key]) return 0
                            const deps = byKey[key].depends.filter(d => byKey[d])
                            const d = deps.length === 0 ? 0 : 1 + Math.max(...deps.map(k => depthOf(k, seen.concat([key]))))
                            depth[key] = d
                            return d
                        }
                        const columns = []
                        for (const op of operations) {
                            const d = depthOf(op.key, [])
                            columns[d] = (columns[d] || []).concat([op.key])
                        }
                        const columnCount = Math.max(1, columns.length)
                        // Cards narrow (down to 170) before the graph scrolls, and
                        // the columns spread to fit the frame up to a comfortable gap.
                        const gap = 48
                        const card = Math.max(170, Math.min(220, (graphFrame.width - 40 - (columnCount - 1) * gap) / columnCount))
                        const step = columnCount < 2 ? 0 : Math.max(card + gap, Math.min(card + 140, (graphFrame.width - 40 - card) / (columnCount - 1)))
                        // Within a column, each operation sits near the average row
                        // of what it depends on, so supply lines cross less.
                        const row = {}
                        for (let c = 0; c < columns.length; ++c) {
                            const keys = columns[c] || []
                            if (c > 0) {
                                const weight = key => {
                                    const deps = byKey[key].depends.filter(d => row[d] !== undefined)
                                    return deps.length === 0 ? 1e9 : deps.reduce((sum, d) => sum + row[d], 0) / deps.length
                                }
                                keys.sort((a, b) => weight(a) - weight(b))
                            }
                            keys.forEach((key, r) => row[key] = (r + 0.5) / keys.length)
                        }
                        let tallest = 0
                        for (let c = 0; c < columns.length; ++c)
                            tallest = Math.max(tallest, (columns[c] || []).length)
                        const height = Math.max(graphFrame.height, 40 + tallest * 110)
                        for (let c = 0; c < columns.length; ++c) {
                            const keys = columns[c] || []
                            const top = Math.max(24, (height - keys.length * 110) / 2)
                            for (let r = 0; r < keys.length; ++r)
                                result[keys[r]] = { x: 20 + c * step, y: top + r * 110, column: c }
                        }
                        result["__size"] = { width: 40 + (columnCount - 1) * step + card, height: height }
                        result["__columns"] = columnCount
                        result["__step"] = step
                        result["__card"] = card
                        return result
                    }
                    onLayoutChanged: lines.requestPaint()

                    Flickable {
                        id: graph
                        anchors.fill: parent
                        visible: !board.showTimeline
                        contentWidth: graphFrame.layout.__size ? graphFrame.layout.__size.width : width
                        contentHeight: graphFrame.layout.__size ? graphFrame.layout.__size.height : height
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true
                        ScrollBar.horizontal: ScrollBar {}
                        ScrollBar.vertical: ScrollBar {}

                    // Phase heads over each column, like a notebook's ruled columns.
                    Repeater {
                        model: board.campaign && board.campaign.status !== "planning" ? (graphFrame.layout.__columns || 0) : 0
                        delegate: Text {
                            required property int index
                            x: 20 + index * (graphFrame.layout.__step || 0)
                            y: 6
                            text: "# " + Style.pad(index + 1)
                            color: Style.faint
                            font.family: Style.mono
                            font.variableAxes: Style.narrow
                            font.pixelSize: 10
                        }
                    }

                    Canvas {
                        id: lines
                        width: graph.contentWidth
                        height: graph.contentHeight
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset()
                            if (!board.campaign) return
                            const places = graphFrame.layout
                            for (const op of board.campaign.operations) {
                                const to = places[op.key]
                                if (!to) continue
                                for (const dependency of op.depends) {
                                    const from = places[dependency]
                                    if (!from) continue
                                    const done = board.campaign.operations.some(o => o.key === dependency && o.status === "complete")
                                    ctx.strokeStyle = done ? board.css(theme.accent, 1) : board.css(Style.dim, 0.7)
                                    ctx.lineWidth = done ? 1.5 : 1
                                    ctx.setLineDash(done ? [] : [4, 4])
                                    const card = places.__card
                                    const x1 = from.x + card, y1 = from.y + 44, x2 = to.x, y2 = to.y + 44
                                    ctx.beginPath()
                                    ctx.moveTo(x1, y1)
                                    if (to.column - from.column > 1) {
                                        // A line that skips columns runs along a lane
                                        // between their cards rather than behind them.
                                        const between = Object.keys(places).filter(k => !k.startsWith("__")
                                            && places[k].column > from.column && places[k].column < to.column).map(k => places[k])
                                        const clear = y => between.every(p => y < p.y - 6 || y > p.y + 94)
                                        const lanes = [y1, y2].concat(between.map(p => p.y - 11), between.map(p => p.y + 99))
                                        const middle = (y1 + y2) / 2
                                        const lane = lanes.filter(clear).sort((a, b) => Math.abs(a - middle) - Math.abs(b - middle))[0]
                                        const xa = from.x + places.__step - 14, xb = to.x - places.__step + card + 14
                                        ctx.bezierCurveTo(x1 + 24, y1, xa - 24, lane, xa, lane)
                                        ctx.lineTo(xb, lane)
                                        ctx.bezierCurveTo(xb + 24, lane, x2 - 30, y2, x2 - 6, y2)
                                    } else {
                                        ctx.bezierCurveTo(x1 + 40, y1, x2 - 40, y2, x2 - 6, y2)
                                    }
                                    ctx.stroke()
                                    // A square tick where the line leaves, an arrowhead where it lands.
                                    ctx.setLineDash([])
                                    ctx.fillStyle = ctx.strokeStyle
                                    ctx.fillRect(x1 - 2, y1 - 2, 4, 4)
                                    ctx.beginPath()
                                    ctx.moveTo(x2, y2); ctx.lineTo(x2 - 6, y2 - 3.5); ctx.lineTo(x2 - 6, y2 + 3.5); ctx.fill()
                                }
                            }
                        }
                    }
                    Connections {
                        target: ops
                        function onCampaignsChanged() { lines.requestPaint() }
                    }

                    Repeater {
                        model: board.campaign ? board.campaign.operations : []
                        delegate: Rectangle {
                            id: card
                            required property var modelData
                            readonly property var place: graphFrame.layout[modelData.key] || { x: 0, y: 0 }
                            readonly property color tone: board.draft ? theme.accent : Style.statusColor(modelData.status, theme.accent)
                            readonly property bool chosen: board.editing === modelData.key
                            readonly property bool live: modelData.status === "deployed"
                            x: place.x
                            y: place.y
                            width: graphFrame.layout.__card || 220
                            height: 88
                            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                            Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                            color: chosen ? Style.wash : cardHover.hovered ? Style.raised : Style.panel
                            border.color: chosen || live ? theme.accent : Style.line
                            radius: Math.min(2, theme.radius)
                            Rectangle { visible: card.chosen; width: 2; height: parent.height; color: theme.accent }
                            Brackets { anchors.fill: parent; anchors.margins: -1; visible: card.chosen; size: 7 }
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 10
                                anchors.topMargin: 9
                                anchors.bottomMargin: 12
                                spacing: 3
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Rectangle {
                                        id: cardDot
                                        implicitWidth: 6; implicitHeight: 6
                                        color: board.draft ? Style.dim : card.tone
                                        SequentialAnimation on opacity {
                                            running: card.live
                                            loops: Animation.Infinite
                                            NumberAnimation { to: 0.15; duration: 450 }
                                            NumberAnimation { to: 1; duration: 450 }
                                            onStopped: cardDot.opacity = 1
                                        }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: card.modelData.codename || card.modelData.key
                                        elide: Text.ElideRight
                                        color: Style.text
                                        font.family: Style.mono
                                        font.variableAxes: Style.wide
                                        font.pixelSize: 13
                                        font.letterSpacing: -0.3
                                    }
                                    Text {
                                        visible: (card.modelData.waiting || 0) > 0
                                        text: "◉"
                                        color: Style.danger
                                        font.family: Style.mono
                                        font.pixelSize: 11
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    text: card.live && card.modelData.activity ? "▸ " + card.modelData.activity : card.modelData.objective
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    color: card.live ? theme.accent : Style.dim
                                    font.family: card.live ? Style.mono : Style.body
                                    font.variableAxes: card.live ? Style.narrow : ({})
                                    font.pixelSize: 11
                                    textFormat: Text.PlainText
                                }
                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: board.draft
                                          ? qsTr("%1 · %n cycle(s)", "", card.modelData.cycles).arg(card.modelData.model || qsTr("default"))
                                          : qsTr("%1 · C%2/%3").arg(Style.statusLabel(card.modelData.status))
                                                .arg(card.modelData.cyclesDone || 0).arg(card.modelData.cycles)
                                    color: board.draft ? Style.dim : Style.text2
                                    font.family: Style.mono
                                    font.variableAxes: Style.narrow
                                    font.pixelSize: 10
                                }
                            }
                            // Cycles as cells along the foot, once it runs.
                            CycleTrack {
                                visible: !board.draft
                                x: 12
                                y: parent.height - 6
                                width: parent.width - 22
                                cycles: Math.max(1, card.modelData.cycles || 1)
                                done: card.modelData.cyclesDone || 0
                                live: card.live
                                segmentHeight: 2
                                labels: false
                            }
                            HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    if (board.draft) {
                                        board.commitEditor()
                                        board.editing = board.editing === card.modelData.key ? "" : card.modelData.key
                                    }
                                    else if (card.modelData.row >= 0)
                                        board.operationPicked(card.modelData.row)
                                }
                            }
                        }
                    }
                    }

                    // The timeline: a lane per operation, time left to right. The
                    // lane names and the axis stay put while the runs scroll.
                    Flickable {
                        id: timelineView
                        readonly property var model: board.timeline
                        readonly property bool started: model.started
                        readonly property real gutter: board.narrow ? 150 : 196
                        readonly property real axisHeight: 30
                        readonly property real padLeft: 16
                        readonly property real padRight: 48
                        readonly property real laneHeight: Math.max(40, Math.min(64, (height - axisHeight - 10) / Math.max(1, model.lanes.length)))
                        readonly property real rangeEnd: !started ? 0 : model.live ? Math.max(board.now, model.end) : model.end
                        readonly property real span: Math.max(60000, rangeEnd - model.start)
                        // Fits the frame, but never under 40px an hour: longer campaigns scroll.
                        readonly property real px: Math.max((width - gutter - padLeft - padRight) / span, 40 / 3600000)
                        readonly property real lanesBottom: axisHeight + model.lanes.length * laneHeight
                        function xAt(t) { return gutter + padLeft + (t - model.start) * px }
                        readonly property var ticks: {
                            if (!started)
                                return []
                            const first = new Date(model.start)
                            const multiDay = first.toDateString() !== new Date(rangeEnd).toDateString()
                            const minGap = multiDay ? 120 : 64
                            const minutes = [1, 2, 5, 10, 15, 30, 60, 120, 180, 360, 720, 1440]
                            let step = minutes.find(m => m * 60000 * px >= minGap)
                            step = (step || Math.ceil(minGap / (1440 * 60000 * px)) * 1440) * 60000
                            const midnight = new Date(model.start)
                            midnight.setHours(0, 0, 0, 0)
                            let t = midnight.getTime() + Math.ceil((model.start - midnight.getTime()) / step) * step
                            const result = []
                            let lastDay = ""
                            for (; t <= rangeEnd && result.length < 400; t += step) {
                                const d = new Date(t)
                                const day = d.toDateString()
                                const label = multiDay && day !== lastDay
                                        ? Qt.locale().toString(d, "ddd d") + " " + Qt.formatDateTime(d, "hh:mm")
                                        : Qt.formatDateTime(d, "hh:mm")
                                lastDay = day
                                result.push({ at: t, label: label })
                            }
                            return result
                        }
                        anchors.fill: parent
                        anchors.margins: 1
                        visible: board.showTimeline
                        contentWidth: started ? Math.max(width, gutter + padLeft + span * px + padRight) : width
                        contentHeight: Math.max(height, lanesBottom + 12)
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true
                        ScrollBar.horizontal: ScrollBar {}
                        ScrollBar.vertical: ScrollBar {}
                        // A live campaign opens on its latest moments.
                        onVisibleChanged: if (visible && model.live) contentX = Math.max(0, contentWidth - width)

                        // Ruled time: a hairline per tick down through the lanes.
                        Repeater {
                            model: timelineView.ticks
                            delegate: Rectangle {
                                required property var modelData
                                x: Math.round(timelineView.xAt(modelData.at))
                                y: timelineView.axisHeight
                                width: 1
                                height: timelineView.lanesBottom - timelineView.axisHeight
                                color: Style.line
                            }
                        }
                        // Merges: where an operation's work was extracted into the project.
                        Repeater {
                            model: timelineView.model.merges
                            delegate: Rectangle {
                                required property var modelData
                                x: Math.round(timelineView.xAt(modelData.at))
                                y: timelineView.axisHeight
                                width: 1
                                height: timelineView.lanesBottom - timelineView.axisHeight
                                color: Style.lineStrong
                            }
                        }

                        Repeater {
                            model: timelineView.model.lanes
                            delegate: Item {
                                id: lane
                                required property var modelData
                                required property int index
                                readonly property var op: modelData.op
                                readonly property real middle: height / 2
                                y: timelineView.axisHeight + index * timelineView.laneHeight
                                width: timelineView.contentWidth
                                height: timelineView.laneHeight
                                Rectangle { y: parent.height - 1; width: parent.width; height: 1; color: Style.line }

                                // Not started: the planned order only.
                                Text {
                                    visible: !timelineView.started
                                    x: timelineView.gutter + timelineView.padLeft
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - x - 16
                                    elide: Text.ElideRight
                                    text: qsTr("Not started") + (lane.modelData.waitingOn.length > 0
                                          ? "  ·  " + qsTr("after %1").arg(lane.modelData.waitingOn.join(", ")) : "")
                                    color: Style.faint
                                    font.family: Style.mono
                                    font.variableAxes: Style.narrow
                                    font.pixelSize: 11
                                }

                                // The operation's span, first run to last, as a firm hairline.
                                Rectangle {
                                    readonly property real from: lane.modelData.runs.length > 0 ? lane.modelData.first : NaN
                                    readonly property real to: lane.modelData.liveRun ? board.now
                                                               : lane.modelData.runs.reduce((m, r) => Math.max(m, r.end), -Infinity)
                                    visible: timelineView.started && !isNaN(from) && isFinite(to)
                                    x: timelineView.xAt(from)
                                    y: Math.round(lane.middle)
                                    width: Math.max(0, (to - from) * timelineView.px)
                                    height: 1
                                    color: Style.lineStrong
                                }

                                // Waiting on what it depends on, dashed and faint.
                                Item {
                                    id: wait
                                    readonly property var span: lane.modelData.wait
                                    readonly property real to: span ? (span.end === -1 ? board.now : span.end) : 0
                                    readonly property string label: lane.modelData.waitingOn.length > 0
                                        ? qsTr("Waiting on %1").arg(lane.modelData.waitingOn.join(", ")) : qsTr("Waiting")
                                    visible: timelineView.started && span !== null && span !== undefined
                                    x: span ? timelineView.xAt(span.start) : 0
                                    y: Math.round(lane.middle) - 8
                                    width: span ? Math.max(1, (to - span.start) * timelineView.px) : 0
                                    height: 16
                                    Shape {
                                        y: 8
                                        width: parent.width; height: 1
                                        ShapePath {
                                            strokeColor: Style.faint
                                            strokeWidth: 1
                                            strokeStyle: ShapePath.DashLine
                                            dashPattern: [3, 3]
                                            fillColor: "transparent"
                                            startX: 0; startY: 0.5
                                            PathLine { x: wait.width; y: 0.5 }
                                        }
                                    }
                                    Text {
                                        // Kept clear of the pinned lane names while there's room.
                                        readonly property real clearOf: timelineView.contentX + timelineView.gutter + 6 - wait.x
                                        visible: implicitWidth + 12 < wait.width
                                        x: Math.max(6, Math.min(wait.width - implicitWidth - 6, clearOf))
                                        y: -6
                                        text: wait.label
                                        color: Style.faint
                                        font.family: Style.mono
                                        font.variableAxes: Style.narrow
                                        font.pixelSize: 10
                                    }
                                    HoverHandler {
                                        id: waitHover
                                        onHoveredChanged: board.showTip(hovered, wait, wait.label + " · "
                                            + board.duration((wait.to - wait.span.start) / 1000))
                                    }
                                }

                                // The cycle runs, coloured by how each ended.
                                Repeater {
                                    model: lane.modelData.runs
                                    delegate: Rectangle {
                                        id: run
                                        required property var modelData
                                        readonly property real w: (modelData.end - modelData.start) * timelineView.px
                                        readonly property string tip: qsTr("%1 · cycle %2 · %3 · ≈%4 · %5")
                                            .arg(lane.op.codename || lane.op.key).arg(modelData.cycle)
                                            .arg(board.duration(modelData.seconds)).arg(board.money(modelData.cost))
                                            .arg(board.outcomeLabel(modelData.outcome))
                                        visible: timelineView.started
                                        x: timelineView.xAt(modelData.start)
                                        y: Math.round(lane.middle) - 7
                                        width: Math.max(3, w > 5 ? w - 1 : w)
                                        height: 14
                                        color: board.outcomeColor(modelData.outcome)
                                        border.color: runHover.hovered ? Style.text : "transparent"
                                        HoverHandler {
                                            id: runHover
                                            onHoveredChanged: board.showTip(hovered, run, run.tip)
                                        }
                                    }
                                }

                                // A run under way grows to now, its leading edge pulsing.
                                Rectangle {
                                    id: liveRun
                                    readonly property var info: lane.modelData.liveRun
                                    readonly property string tip: info ? qsTr("%1 · cycle %2 · %3 · ≈%4 · %5")
                                        .arg(lane.op.codename || lane.op.key).arg(info.cycle)
                                        .arg(board.duration((board.now - info.start) / 1000)).arg(board.money(info.cost))
                                        .arg(board.outcomeLabel("live")) : ""
                                    visible: timelineView.started && info !== null
                                    x: info ? timelineView.xAt(info.start) : 0
                                    y: Math.round(lane.middle) - 7
                                    width: info ? Math.max(3, (board.now - info.start) * timelineView.px) : 0
                                    height: 14
                                    color: "transparent"
                                    border.color: liveHover.hovered ? Style.text : "transparent"
                                    Rectangle { anchors.fill: parent; z: -1; color: theme.accent; opacity: 0.6 }
                                    Rectangle {
                                        id: liveEdge
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 2
                                        height: parent.height + 8
                                        color: theme.accent
                                        SequentialAnimation on opacity {
                                            running: liveRun.visible && timelineView.visible && !Prefs.reduceMotion
                                            loops: Animation.Infinite
                                            NumberAnimation { to: 0.15; duration: 600 }
                                            NumberAnimation { to: 1; duration: 600 }
                                            onStopped: liveEdge.opacity = 1
                                        }
                                    }
                                    HoverHandler {
                                        id: liveHover
                                        onHoveredChanged: board.showTip(hovered, liveRun, liveRun.tip)
                                    }
                                }

                                // Where its work was merged in.
                                Repeater {
                                    model: lane.modelData.merges
                                    delegate: Text {
                                        id: merge
                                        required property var modelData
                                        visible: timelineView.started
                                        x: Math.round(timelineView.xAt(modelData)) - width / 2 + 0.5
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "◆"
                                        color: Style.good
                                        font.family: Style.mono
                                        font.pixelSize: 11
                                        HoverHandler {
                                            onHoveredChanged: board.showTip(hovered, merge, qsTr("%1 merged · %2")
                                                .arg(lane.op.codename || lane.op.key).arg(Qt.formatDateTime(new Date(merge.modelData), "hh:mm")))
                                        }
                                    }
                                }

                                // The lane's name, pinned at the left as the runs scroll under it.
                                Rectangle {
                                    id: laneName
                                    x: timelineView.contentX
                                    z: 3
                                    width: timelineView.gutter
                                    height: parent.height
                                    color: laneHover.hovered ? Style.raised : Style.bg
                                    readonly property bool chosen: board.editing === lane.op.key
                                    Rectangle { visible: laneName.chosen; width: 2; height: parent.height; color: theme.accent }
                                    Rectangle { y: parent.height - 1; width: parent.width; height: 1; color: Style.line }
                                    Rectangle { x: parent.width - 1; width: 1; height: parent.height; color: Style.lineStrong }
                                    ColumnLayout {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 12
                                        spacing: 2
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            Rectangle {
                                                implicitWidth: 6; implicitHeight: 6
                                                color: board.draft ? Style.dim : Style.statusColor(lane.op.status, theme.accent)
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: lane.op.codename || lane.op.key
                                                elide: Text.ElideRight
                                                color: laneName.chosen ? Style.text : Style.text2
                                                font.family: Style.mono
                                                font.variableAxes: Style.wide
                                                font.pixelSize: 12
                                                font.letterSpacing: -0.3
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            Layout.leftMargin: 14
                                            visible: timelineView.laneHeight >= 40
                                            elide: Text.ElideRight
                                            text: board.draft || !timelineView.started
                                                  ? qsTr("%n cycle(s)", "", lane.op.cycles || 0)
                                                  : qsTr("C%1/%2 · %3").arg(lane.op.cyclesDone || 0).arg(lane.op.cycles || 0)
                                                        .arg(board.duration(lane.modelData.total))
                                            color: Style.dim
                                            font.family: Style.mono
                                            font.variableAxes: Style.narrow
                                            font.pixelSize: 10
                                            font.features: { "tnum": 1 }
                                        }
                                    }
                                    HoverHandler { id: laneHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler {
                                        onTapped: {
                                            if (board.draft) {
                                                board.commitEditor()
                                                board.editing = board.editing === lane.op.key ? "" : lane.op.key
                                            }
                                            else if (lane.op.row >= 0)
                                                board.operationPicked(lane.op.row)
                                        }
                                    }
                                }
                            }
                        }

                        // Now: an accent rule through every lane.
                        Rectangle {
                            visible: timelineView.started && timelineView.model.live
                            x: Math.round(timelineView.xAt(board.now))
                            y: timelineView.axisHeight
                            z: 2
                            width: 1
                            height: timelineView.lanesBottom - timelineView.axisHeight + 6
                            color: theme.accent
                        }

                        // The axis along the top, pinned as the lanes scroll.
                        Rectangle {
                            id: axis
                            y: timelineView.contentY
                            z: 4
                            width: timelineView.contentWidth
                            height: timelineView.axisHeight
                            color: Style.bg
                            Rectangle { y: parent.height - 1; width: parent.width; height: 1; color: Style.lineStrong }
                            Repeater {
                                model: timelineView.ticks
                                delegate: Item {
                                    required property var modelData
                                    x: Math.round(timelineView.xAt(modelData.at))
                                    height: axis.height
                                    Rectangle { y: parent.height - 5; width: 1; height: 4; color: Style.lineStrong }
                                    Text {
                                        x: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: parent.modelData.label
                                        color: Style.dim
                                        font.family: Style.mono
                                        font.variableAxes: Style.narrow
                                        font.pixelSize: 10
                                        font.features: { "tnum": 1 }
                                    }
                                }
                            }
                            Repeater {
                                model: timelineView.model.merges
                                delegate: Text {
                                    required property var modelData
                                    x: Math.round(timelineView.xAt(modelData.at)) - width / 2 + 0.5
                                    y: parent.height - height + 1
                                    text: "◆"
                                    color: Style.good
                                    font.family: Style.mono
                                    font.pixelSize: 8
                                }
                            }
                            Rectangle {
                                visible: timelineView.started && timelineView.model.live
                                x: Math.round(timelineView.xAt(board.now)) - width + 1
                                anchors.verticalCenter: parent.verticalCenter
                                width: nowText.implicitWidth + 10
                                height: 16
                                color: theme.accent
                                Text {
                                    id: nowText
                                    anchors.centerIn: parent
                                    text: qsTr("now")
                                    color: theme.accentForeground
                                    font.family: Style.mono
                                    font.variableAxes: Style.narrowMedium
                                    font.pixelSize: 10
                                }
                            }
                        }
                        // The corner over the lane names: how long the campaign has run.
                        Rectangle {
                            x: timelineView.contentX
                            y: timelineView.contentY
                            z: 5
                            width: timelineView.gutter
                            height: timelineView.axisHeight
                            color: Style.bg
                            Rectangle { y: parent.height - 1; width: parent.width; height: 1; color: Style.lineStrong }
                            Rectangle { x: parent.width - 1; width: 1; height: parent.height; color: Style.lineStrong }
                            Text {
                                x: 14
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 24
                                elide: Text.ElideRight
                                text: "# " + (timelineView.started
                                      ? board.duration((timelineView.rangeEnd - timelineView.model.start) / 1000)
                                      : qsTr("Planned order").toLowerCase())
                                color: Style.dim
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 10
                            }
                        }
                    }

                    // The timeline's tooltip, over whatever is hovered.
                    Rectangle {
                        id: tip
                        property Item target: null
                        property string text: ""
                        readonly property point at: {
                            if (!target) return Qt.point(0, 0)
                            // Re-placed as the lanes scroll or the run grows.
                            void (timelineView.contentX + timelineView.contentY + target.width + target.x)
                            return target.mapToItem(graphFrame, target.width / 2, 0)
                        }
                        visible: target !== null && board.showTimeline
                        z: 10
                        x: Math.max(6, Math.min(graphFrame.width - width - 6, at.x - width / 2))
                        y: at.y - height - 6 < 4 ? at.y + (target ? target.height : 0) + 6 : at.y - height - 6
                        width: tipText.implicitWidth + 20
                        height: tipText.implicitHeight + 12
                        color: Style.panel
                        border.color: Style.lineStrong
                        radius: Math.min(2, theme.radius)
                        Text {
                            id: tipText
                            anchors.centerIn: parent
                            text: tip.text
                            color: Style.text
                            font.family: Style.mono
                            font.variableAxes: Style.narrow
                            font.pixelSize: 11
                        }
                    }

                    // Planning: the planner at work.
                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: board.campaign !== null && board.campaign.status === "planning"
                        spacing: 12
                        Crosshair { Layout.alignment: Qt.AlignHCenter }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: qsTr("Planning the campaign")
                            color: Style.text
                            font.family: Style.display
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                            font.letterSpacing: -0.3
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: board.campaign && board.campaign.activity ? "▸ " + board.campaign.activity : ""
                            color: theme.accent
                            font.family: Style.mono
                            font.variableAxes: Style.narrow
                            font.pixelSize: 12
                        }
                    }
                }

                // Editing one planned operation.
                Rectangle {
                    id: editor
                    readonly property var op: {
                        if (!board.campaign || board.editing === "") return null
                        for (const o of board.campaign.operations)
                            if (o.key === board.editing) return o
                        return null
                    }
                    Layout.fillWidth: true
                    visible: board.draft && op !== null
                    implicitHeight: editorColumn.implicitHeight + 28
                    color: Style.raised
                    border.color: Style.lineStrong
                    radius: Math.min(2, theme.radius)
                    onOpChanged: if (op) { editCodename.text = op.codename; editObjective.text = op.objective }
                    Rectangle { width: 2; height: parent.height; color: theme.accent }
                    ColumnLayout {
                        id: editorColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 14
                        anchors.leftMargin: 18
                        spacing: 10
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            TextField {
                                id: editCodename
                                Layout.preferredWidth: board.narrow ? 150 : 210
                                placeholderText: qsTr("Codename")
                                // A callsign: stored in capitals.
                                font.family: Style.mono
                                font.variableAxes: Style.wide
                                // A callsign, so it's typed in capitals; the field's own
                                // label stays in sentence case.
                                onTextEdited: { const at = cursorPosition; const upper = text.toUpperCase(); if (upper !== text) { text = upper; cursorPosition = at } }
                                onEditingFinished: if (editor.op) board.planWith(editor.op.key, { codename: text.toUpperCase() })
                            }
                            TextField {
                                id: editObjective
                                Layout.fillWidth: true
                                placeholderText: qsTr("Objective")
                                font.family: Style.body
                                font.pixelSize: 13
                                onEditingFinished: if (editor.op && text.trim().length > 0) board.planWith(editor.op.key, { objective: text })
                            }
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 10
                            Row {
                                spacing: 8
                                TacticalButton { text: "−"; enabled: editor.op && editor.op.cycles > 1; onClicked: board.planWith(editor.op.key, { cycles: editor.op.cycles - 1 }) }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(implicitWidth, 72)
                                    horizontalAlignment: Text.AlignHCenter
                                    text: editor.op ? qsTr("%n cycle(s)", "", editor.op.cycles) : ""
                                    color: Style.text
                                    font.family: Style.mono
                                    font.variableAxes: Style.narrow
                                    font.pixelSize: 12
                                    font.features: { "tnum": 1 }
                                }
                                TacticalButton { text: "+"; enabled: editor.op && editor.op.cycles < 20; onClicked: board.planWith(editor.op.key, { cycles: editor.op.cycles + 1 }) }
                            }
                            ComboBox {
                                width: 170
                                font.family: Style.body
                                readonly property var keys: ["", "opus", "sonnet", "haiku"]
                                model: [qsTr("Account default"), "opus", "sonnet", "haiku"]
                                currentIndex: editor.op ? Math.max(0, keys.indexOf(editor.op.model)) : 0
                                onActivated: (index) => board.planWith(editor.op.key, { model: keys[index] })
                            }
                            TacticalButton { text: qsTr("Remove"); danger: true; onClicked: board.removeFromPlan(editor.op.key) }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Text {
                                Layout.alignment: Qt.AlignTop
                                Layout.topMargin: 4
                                text: qsTr("After")
                                color: Style.text2
                                font.family: Style.body
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }
                            // Dependencies, toggled; a loop is refused.
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6
                                Repeater {
                                    model: board.campaign ? board.campaign.operations.filter(o => editor.op && o.key !== editor.op.key) : []
                                    delegate: Rectangle {
                                        id: dependency
                                        required property var modelData
                                        readonly property bool on: editor.op && editor.op.depends.indexOf(modelData.key) >= 0
                                        width: dependencyText.implicitWidth + 20 + (on ? 12 : 0)
                                        height: 24
                                        color: on ? Style.wash : dependencyHover.hovered ? Style.panel : "transparent"
                                        border.color: on ? theme.accent : Style.line
                                        radius: Math.min(2, theme.radius)
                                        Rectangle {
                                            visible: dependency.on
                                            x: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 6; height: 6
                                            color: theme.accent
                                        }
                                        Text {
                                            id: dependencyText
                                            x: dependency.on ? 22 : 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: dependency.modelData.codename || dependency.modelData.key
                                            color: dependency.on ? Style.text : Style.dim
                                            font.family: Style.mono
                                            font.variableAxes: Style.narrow
                                            font.pixelSize: 11
                                        }
                                        HoverHandler { id: dependencyHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler {
                                            onTapped: {
                                                const depends = dependency.on ? editor.op.depends.filter(d => d !== dependency.modelData.key)
                                                                             : editor.op.depends.concat([dependency.modelData.key])
                                                board.planWith(editor.op.key, { depends: depends })
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Approving: how its operations run.
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line; visible: board.budgetable }
                // One line when it fits; when narrow, the budget goes under "Deploy as".
                GridLayout {
                    id: approval
                    readonly property bool oneLine: !board.draft || width >= 720
                    Layout.fillWidth: true
                    visible: board.budgetable
                    columns: board.draft && oneLine ? 6 : 3
                    columnSpacing: 10
                    rowSpacing: 8
                    Text {
                        visible: board.draft
                        text: qsTr("Deploy as")
                        color: Style.text2
                        font.family: Style.body
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    ComboBox {
                        id: campaignRoe
                        visible: board.draft
                        Layout.preferredWidth: board.narrow ? 140 : 170
                        font.family: Style.body
                        readonly property var keys: ["supervised", "restricted", "free"]
                        model: [qsTr("Supervised"), qsTr("Restricted"), qsTr("Weapons free")]
                    }
                    ComboBox {
                        id: campaignOverwatch
                        visible: board.draft
                        Layout.preferredWidth: board.narrow ? 196 : 220
                        font.family: Style.body
                        readonly property var keys: ["review", "fix", "off"]
                        model: [qsTr("Overwatch: review"), qsTr("Overwatch: fix"), qsTr("No overwatch")]
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !board.draft
                        text: qsTr("At its budget, the campaign's operations finish their current cycle and hold.")
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        color: Style.dim
                        font.family: Style.body
                        font.pixelSize: 12
                    }
                    Item { Layout.fillWidth: true; visible: board.draft && approval.oneLine }
                    Text {
                        text: qsTr("Budget")
                        color: Style.text2
                        font.family: Style.body
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    // API value for the whole campaign; empty or 0 is none. Applied on Enter.
                    TextField {
                        id: budgetField
                        implicitWidth: 112
                        implicitHeight: 34
                        topPadding: 4
                        bottomPadding: 4
                        leftPadding: 26
                        rightPadding: 10
                        horizontalAlignment: TextInput.AlignRight
                        color: Style.text
                        inputMethodHints: Qt.ImhFormattedNumbersOnly
                        validator: DoubleValidator { bottom: 0; top: 100000; decimals: 2; notation: DoubleValidator.StandardNotation }
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                        font.pixelSize: 13
                        font.features: { "tnum": 1 }
                        selectByMouse: true
                        // Selected on entry; shows the saved budget again on leaving,
                        // so it never shows a figure that wasn't applied.
                        onActiveFocusChanged: {
                            if (activeFocus)
                                selectAll()
                            else
                                text = board.campaign && board.campaign.budget > 0 ? Number(board.campaign.budget).toFixed(2) : ""
                        }
                        background: Rectangle {
                            color: Style.bg
                            border.color: budgetField.activeFocus ? theme.accent : Style.line
                            radius: Math.min(2, theme.radius)
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: "$"
                                color: Style.dim
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 13
                            }
                            Text {
                                visible: budgetField.text.length === 0
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("None")
                                color: Style.faint
                                font.family: Style.body
                                font.pixelSize: 12
                            }
                        }
                        onAccepted: { board.applyBudget(); focus = false }
                    }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }
                // The button row: leaving and record keeping on the left, the
                // campaign's next move on the right. Wraps when narrow.
                Flow {
                    id: actions
                    Layout.fillWidth: true
                    spacing: 10
                    layoutDirection: Qt.LeftToRight
                    Row {
                        id: leftActions
                        spacing: 10
                        TacticalButton { text: qsTr("Close"); key: "Esc"; onClicked: board.close() }
                        TacticalButton {
                            visible: board.campaign !== null && board.campaign.status !== "draft" && board.campaign.status !== "planning"
                                     && board.campaign.status !== "failed"
                            text: qsTr("Dossier")
                            onClicked: ops.openCampaignDossier(board.current)
                        }
                        TacticalButton {
                            visible: board.campaign !== null && (board.campaign.status === "active" || board.campaign.status === "complete"
                                                                 || board.campaign.status === "blocked")
                            text: qsTr("Export")
                            onClicked: campaignExport.popup()
                            Menu {
                                id: campaignExport
                                MenuItem { text: qsTr("HTML report"); onTriggered: ops.reveal(ops.exportCampaign(board.current, "html")) }
                                MenuItem { text: qsTr("Markdown write-up"); onTriggered: ops.reveal(ops.exportCampaign(board.current, "md")) }
                            }
                        }
                        TacticalButton {
                            visible: board.campaign !== null && board.campaign.status !== "active"
                            text: qsTr("Delete campaign")
                            danger: true
                            onClicked: { ops.removeCampaign(board.current); board.current = ""; if (ops.campaigns.length > 0) board.current = ops.campaigns[0].id; else board.startNew() }
                        }
                    }
                    // Pushes the right-hand group to the edge when both fit on one line.
                    Item {
                        width: actions.width - leftActions.implicitWidth - rightActions.implicitWidth - 2 * actions.spacing
                        height: 1
                        visible: width > 0
                    }
                    Row {
                        id: rightActions
                        spacing: 10
                        TacticalButton {
                            visible: board.draft
                            text: qsTr("Add operation")
                            onClicked: board.addToPlan()
                        }
                        TacticalButton {
                            visible: board.campaign !== null && (board.campaign.status === "failed" || board.campaign.status === "draft")
                            text: qsTr("Replan")
                            onClicked: ops.replanCampaign(board.current)
                        }
                        TacticalButton {
                            visible: board.campaign !== null && board.campaign.status === "blocked"
                            text: qsTr("Resume campaign")
                            primary: true
                            onClicked: ops.resumeCampaign(board.current)
                        }
                        TacticalButton {
                            visible: board.draft
                            text: qsTr("Approve and deploy")
                            key: "Ctrl+Enter"
                            primary: true
                            onClicked: board.approve()
                        }
                    }
                }
            }
        }
    }

    Shortcut {
        enabled: board.visible && !board.creating && board.canToggle
        sequence: "Ctrl+T"
        context: Qt.ApplicationShortcut
        onActivated: board.view = board.view === "timeline" ? "graph" : "timeline"
    }
    Shortcut {
        enabled: board.visible
        sequences: ["Ctrl+Return", "Ctrl+Enter"]
        context: Qt.ApplicationShortcut
        onActivated: {
            if (board.creating) board.plan()
            else if (board.draft) board.approve()
        }
    }
}
