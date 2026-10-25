import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

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
                    // A callsign: stored in capitals.
                    font.family: Style.mono
                    font.variableAxes: Style.wide
                    font.capitalization: Font.AllUppercase
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
                    Text {
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: 6
                        visible: board.campaign !== null && board.campaign.cost > 0
                        text: board.campaign ? "# " + qsTr("Planning ≈ $%1").arg(Number(board.campaign.cost).toLocaleString(Qt.locale(), 'f', 2)) : ""
                        color: Style.dim
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                        font.pixelSize: 11
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
                        // Spread to fit the frame, but never closer than a card
                        // and its arrow; past that the graph scrolls.
                        const step = columnCount < 2 ? 0 : Math.max(245, Math.min(360, (graphFrame.width - 260) / (columnCount - 1)))
                        let tallest = 0
                        for (let c = 0; c < columns.length; ++c)
                            tallest = Math.max(tallest, (columns[c] || []).length)
                        const height = Math.max(graphFrame.height, 40 + tallest * 110)
                        for (let c = 0; c < columns.length; ++c) {
                            const keys = columns[c] || []
                            const top = Math.max(20, (height - keys.length * 110) / 2)
                            for (let r = 0; r < keys.length; ++r)
                                result[keys[r]] = { x: 20 + c * step, y: top + r * 110 }
                        }
                        result["__size"] = { width: 40 + (columnCount - 1) * step + 220, height: height }
                        result["__columns"] = columnCount
                        result["__step"] = step
                        return result
                    }
                    onLayoutChanged: lines.requestPaint()

                    Flickable {
                        id: graph
                        anchors.fill: parent
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
                            y: 5
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
                                    const x1 = from.x + 220, y1 = from.y + 44, x2 = to.x, y2 = to.y + 44
                                    ctx.beginPath()
                                    ctx.moveTo(x1, y1)
                                    ctx.bezierCurveTo(x1 + 40, y1, x2 - 40, y2, x2 - 6, y2)
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
                            width: 220
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
                                font.capitalization: Font.AllUppercase
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
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line; visible: board.draft }
                RowLayout {
                    Layout.fillWidth: true
                    visible: board.draft
                    spacing: 10
                    Text {
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
                    Item { Layout.fillWidth: true }
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
        enabled: board.visible
        sequences: ["Ctrl+Return", "Ctrl+Enter"]
        context: Qt.ApplicationShortcut
        onActivated: {
            if (board.creating) board.plan()
            else if (board.draft) board.approve()
        }
    }
}
