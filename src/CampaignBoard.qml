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
    function close() { visible = false }
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

    Connections {
        target: folderPicker
        function onPicked(path) { if (board.picking) { directoryField.text = path; board.picking = false } }
        function onFailed(message) { if (board.picking) { error.text = message; board.picking = false } }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.84)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: board.close() }
    }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: parent.width - 48
        height: parent.height - 48
        color: Qt.rgba(0.035, 0.043, 0.055, 0.98)
        border.color: Style.line
        radius: theme.radius
        // Clicks on the panel itself mustn't reach the dismissing backdrop.
        MouseArea { anchors.fill: parent }
        Rectangle { width: parent.width; height: 3; color: theme.accent }

        ParallelAnimation {
            id: enter
            NumberAnimation { target: sheet; property: "opacity"; from: 0; to: 1; duration: 160 }
            NumberAnimation { target: sheet; property: "scale"; from: 0.98; to: 1; duration: 220; easing.type: Easing.OutCubic }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 24

            // Every campaign, newest first.
            ColumnLayout {
                Layout.preferredWidth: 260
                Layout.maximumWidth: 260
                Layout.fillHeight: true
                spacing: 10
                ColumnLayout {
                    spacing: 2
                    Text {
                        text: qsTr("Command // theatre")
                        color: theme.accent
                        font.family: Style.mono
                        font.pixelSize: 11
                        font.letterSpacing: 4 * Style.tracking
                        font.capitalization: Font.AllUppercase
                    }
                    Text {
                        text: qsTr("Campaigns")
                        color: Style.text
                        font.family: Style.display
                        font.pixelSize: 30
                        font.weight: Font.Black
                        font.letterSpacing: 5 * Style.tracking
                        font.capitalization: Font.AllUppercase
                    }
                }
                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 6
                    model: ops.campaigns
                    delegate: Item {
                        id: entry
                        required property var modelData
                        readonly property bool chosen: !board.creating && board.current === modelData.id
                        width: ListView.view.width
                        height: 62
                        Rectangle {
                            anchors.fill: parent
                            color: entry.chosen ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.14)
                                 : entryHover.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                            border.color: entry.chosen ? theme.accent : Style.line
                            radius: Math.min(4, theme.radius)
                        }
                        Rectangle { width: 3; height: parent.height; color: board.statusColor(entry.modelData.status) }
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 10
                            anchors.topMargin: 8
                            anchors.bottomMargin: 8
                            spacing: 2
                            Text {
                                Layout.fillWidth: true
                                text: entry.modelData.name
                                elide: Text.ElideRight
                                color: Style.text
                                font.family: Style.display
                                font.pixelSize: 15
                                font.weight: Font.Black
                                font.letterSpacing: 2 * Style.tracking
                            }
                            Text {
                                Layout.fillWidth: true
                                text: board.statusLabel(entry.modelData.status).toUpperCase() + " · "
                                      + qsTr("%n operation(s)", "", entry.modelData.operations.length)
                                elide: Text.ElideRight
                                color: board.statusColor(entry.modelData.status)
                                font.family: Style.mono
                                font.pixelSize: 10
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
                    text: qsTr("Give the whole objective. A planner (read-only, it changes nothing) surveys the project and breaks it into operations with dependencies, for you to review before anything runs.")
                    wrapMode: Text.Wrap
                    color: Style.dim
                    font.family: Style.display
                    font.pixelSize: 13
                }
                TextField {
                    id: nameField
                    Layout.fillWidth: true
                    placeholderText: qsTr("Campaign name")
                    font.family: Style.display
                    font.weight: Font.Black
                    font.letterSpacing: 3 * Style.tracking
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
                        font.family: Style.display
                        font.pixelSize: 14
                    }
                }
                RowLayout {
                    spacing: 12
                    Text {
                        text: qsTr("Planner")
                        color: Style.dim
                        font.family: Style.display
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.letterSpacing: 3 * Style.tracking
                        font.capitalization: Font.AllUppercase
                    }
                    ComboBox {
                        id: plannerModel
                        Layout.preferredWidth: 200
                        model: [qsTr("Account default"), "opus", "sonnet", "haiku"]
                    }
                }
                Text {
                    id: error
                    Layout.fillWidth: true
                    visible: text.length > 0
                    wrapMode: Text.Wrap
                    color: Style.danger
                    font.family: Style.display
                    font.pixelSize: 13
                    font.weight: Font.Bold
                }
                Item { Layout.fillHeight: true }
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
                        spacing: 2
                        Text {
                            text: board.campaign ? board.statusLabel(board.campaign.status) + "  ·  " + board.campaign.directory : ""
                            color: board.campaign ? board.statusColor(board.campaign.status) : Style.dim
                            font.family: Style.mono
                            font.pixelSize: 11
                            font.letterSpacing: 2 * Style.tracking
                            font.capitalization: Font.AllUppercase
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                        }
                        Text {
                            text: board.campaign ? board.campaign.name : ""
                            color: Style.text
                            font.family: Style.display
                            font.pixelSize: 34
                            font.weight: Font.Black
                            font.letterSpacing: 5 * Style.tracking
                        }
                    }
                    Text {
                        visible: board.campaign !== null && board.campaign.cost > 0
                        text: board.campaign ? qsTr("Planning ≈ $%1").arg(Number(board.campaign.cost).toLocaleString(Qt.locale(), 'f', 2)) : ""
                        color: Style.faint
                        font.family: Style.mono
                        font.pixelSize: 11
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: board.campaign ? board.campaign.objective : ""
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    color: Style.text
                    font.family: Style.display
                    font.pixelSize: 14
                    textFormat: Text.PlainText
                }
                Text {
                    Layout.fillWidth: true
                    visible: board.campaign !== null && (board.campaign.summary.length > 0 || board.campaign.error.length > 0)
                    text: !board.campaign ? "" : board.campaign.error.length > 0 ? "⚠ " + board.campaign.error : board.campaign.summary
                    wrapMode: Text.Wrap
                    color: board.campaign && board.campaign.error.length > 0 ? Style.danger : Style.dim
                    font.family: Style.display
                    font.pixelSize: 13
                    textFormat: Text.PlainText
                }

                // The graph: one column per depth, supply lines between.
                Rectangle {
                    id: graphFrame
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Qt.rgba(0, 0, 0, 0.35)
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
                                    ctx.strokeStyle = done ? theme.accent : "rgba(255,255,255,0.25)"
                                    ctx.lineWidth = done ? 2 : 1.5
                                    ctx.setLineDash(done ? [] : [5, 5])
                                    const x1 = from.x + 220, y1 = from.y + 44, x2 = to.x, y2 = to.y + 44
                                    ctx.beginPath()
                                    ctx.moveTo(x1, y1)
                                    ctx.bezierCurveTo(x1 + 40, y1, x2 - 40, y2, x2, y2)
                                    ctx.stroke()
                                    ctx.fillStyle = ctx.strokeStyle
                                    ctx.beginPath()
                                    ctx.moveTo(x2, y2); ctx.lineTo(x2 - 7, y2 - 4); ctx.lineTo(x2 - 7, y2 + 4); ctx.fill()
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
                            readonly property color tone: Style.statusColor(modelData.status, theme.accent)
                            readonly property bool chosen: board.editing === modelData.key
                            x: place.x
                            y: place.y
                            width: 220
                            height: 88
                            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                            Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                            color: cardHover.hovered || chosen ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0.05, 0.06, 0.08, 0.95)
                            border.color: chosen ? theme.accent : modelData.status === "deployed" ? theme.accent : Style.line
                            border.width: chosen ? 2 : 1
                            radius: Math.min(4, theme.radius)
                            Rectangle { width: 3; height: parent.height; color: board.draft ? theme.accent : card.tone }
                            SequentialAnimation on opacity {
                                running: card.modelData.status === "deployed"
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.75; duration: 700 }
                                NumberAnimation { to: 1; duration: 700 }
                                onStopped: card.opacity = 1
                            }
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 10
                                anchors.topMargin: 8
                                anchors.bottomMargin: 8
                                spacing: 1
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: card.modelData.codename || card.modelData.key
                                        elide: Text.ElideRight
                                        color: Style.text
                                        font.family: Style.display
                                        font.pixelSize: 14
                                        font.weight: Font.Black
                                        font.letterSpacing: 2 * Style.tracking
                                    }
                                    Text {
                                        visible: (card.modelData.waiting || 0) > 0
                                        text: "◉"
                                        color: Style.danger
                                        font.pixelSize: 12
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    text: card.modelData.status === "deployed" && card.modelData.activity ? "▸ " + card.modelData.activity : card.modelData.objective
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    color: card.modelData.status === "deployed" ? theme.accent : Style.dim
                                    font.family: Style.display
                                    font.pixelSize: 11
                                    textFormat: Text.PlainText
                                }
                                Text {
                                    text: board.draft
                                          ? qsTr("%1 · %n cycle(s)", "", card.modelData.cycles).arg(card.modelData.model || qsTr("default"))
                                          : qsTr("%1 · C%2/%3").arg(Style.statusLabel(card.modelData.status).toUpperCase())
                                                .arg(card.modelData.cyclesDone || 0).arg(card.modelData.cycles)
                                    color: board.draft ? Style.faint : card.tone
                                    font.family: Style.mono
                                    font.pixelSize: 10
                                }
                            }
                            HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    if (board.draft)
                                        board.editing = board.editing === card.modelData.key ? "" : card.modelData.key
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
                            font.weight: Font.Black
                            font.letterSpacing: 4 * Style.tracking
                            font.capitalization: Font.AllUppercase
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: board.campaign && board.campaign.activity ? "▸ " + board.campaign.activity : ""
                            color: theme.accent
                            font.family: Style.mono
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
                    implicitHeight: editorColumn.implicitHeight + 24
                    color: Qt.rgba(1, 1, 1, 0.03)
                    border.color: theme.accent
                    radius: Math.min(4, theme.radius)
                    onOpChanged: if (op) { editCodename.text = op.codename; editObjective.text = op.objective }
                    ColumnLayout {
                        id: editorColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12
                        spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            TextField {
                                id: editCodename
                                Layout.preferredWidth: 200
                                placeholderText: qsTr("Codename")
                                font.family: Style.display
                                font.weight: Font.Black
                                font.capitalization: Font.AllUppercase
                                onEditingFinished: if (editor.op) board.planWith(editor.op.key, { codename: text.toUpperCase() })
                            }
                            TextField {
                                id: editObjective
                                Layout.fillWidth: true
                                placeholderText: qsTr("Objective")
                                font.family: Style.display
                                font.pixelSize: 13
                                onEditingFinished: if (editor.op && text.trim().length > 0) board.planWith(editor.op.key, { objective: text })
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            TacticalButton { text: "−"; enabled: editor.op && editor.op.cycles > 1; onClicked: board.planWith(editor.op.key, { cycles: editor.op.cycles - 1 }) }
                            Text {
                                text: editor.op ? qsTr("%n cycle(s)", "", editor.op.cycles) : ""
                                color: Style.text
                                font.family: Style.mono
                                font.pixelSize: 13
                            }
                            TacticalButton { text: "+"; enabled: editor.op && editor.op.cycles < 20; onClicked: board.planWith(editor.op.key, { cycles: editor.op.cycles + 1 }) }
                            ComboBox {
                                Layout.preferredWidth: 170
                                readonly property var keys: ["", "opus", "sonnet", "haiku"]
                                model: [qsTr("Account default"), "opus", "sonnet", "haiku"]
                                currentIndex: editor.op ? Math.max(0, keys.indexOf(editor.op.model)) : 0
                                onActivated: (index) => board.planWith(editor.op.key, { model: keys[index] })
                            }
                            Text {
                                text: qsTr("After")
                                color: Style.dim
                                font.family: Style.display
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                font.letterSpacing: 2 * Style.tracking
                                font.capitalization: Font.AllUppercase
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
                                        width: dependencyText.implicitWidth + 16
                                        height: 24
                                        color: on ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.18) : "transparent"
                                        border.color: on ? theme.accent : Style.line
                                        radius: Math.min(4, theme.radius)
                                        Text {
                                            id: dependencyText
                                            anchors.centerIn: parent
                                            text: dependency.modelData.codename || dependency.modelData.key
                                            color: dependency.on ? Style.text : Style.dim
                                            font.family: Style.mono
                                            font.pixelSize: 10
                                        }
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
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
                            TacticalButton { text: qsTr("Remove"); danger: true; onClicked: board.removeFromPlan(editor.op.key) }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    TacticalButton { text: qsTr("Close"); key: "Esc"; onClicked: board.close() }
                    TacticalButton {
                        visible: board.campaign !== null && board.campaign.status !== "draft" && board.campaign.status !== "planning"
                                 && board.campaign.status !== "failed"
                        text: qsTr("Dossier")
                        onClicked: ops.openCampaignDossier(board.current)
                    }
                    TacticalButton {
                        visible: board.campaign !== null && board.campaign.status !== "active"
                        text: qsTr("Delete campaign")
                        danger: true
                        onClicked: { ops.removeCampaign(board.current); board.current = ""; if (ops.campaigns.length > 0) board.current = ops.campaigns[0].id; else board.startNew() }
                    }
                    Item { Layout.fillWidth: true }
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
                }
                // Approving: how its operations run.
                RowLayout {
                    Layout.fillWidth: true
                    visible: board.draft
                    spacing: 10
                    Text {
                        text: qsTr("Deploy as")
                        color: Style.dim
                        font.family: Style.display
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.letterSpacing: 3 * Style.tracking
                        font.capitalization: Font.AllUppercase
                    }
                    ComboBox {
                        id: campaignRoe
                        visible: board.draft
                        Layout.preferredWidth: 170
                        readonly property var keys: ["supervised", "restricted", "free"]
                        model: [qsTr("Supervised"), qsTr("Restricted"), qsTr("Weapons free")]
                    }
                    ComboBox {
                        id: campaignOverwatch
                        visible: board.draft
                        Layout.preferredWidth: 220
                        readonly property var keys: ["review", "fix", "off"]
                        model: [qsTr("Overwatch: review"), qsTr("Overwatch: fix"), qsTr("No overwatch")]
                    }
                    Item { Layout.fillWidth: true }
                    TacticalButton {
                        visible: board.draft
                        text: qsTr("Approve and deploy")
                        key: "Ctrl+Enter"
                        primary: true
                        onClicked: ops.approveCampaign(board.current, campaignRoe.keys[campaignRoe.currentIndex],
                                                       campaignOverwatch.keys[campaignOverwatch.currentIndex])
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
            else if (board.draft) ops.approveCampaign(board.current, campaignRoe.keys[campaignRoe.currentIndex],
                                                      campaignOverwatch.keys[campaignOverwatch.currentIndex])
        }
    }
}
