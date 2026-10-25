import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The command palette: one field near the top, everything Fireteam can do and
// every operation beneath it, ranked by a fuzzy match as you type. A sentence
// that matches nothing (or runs to three words) becomes a quick deploy.
Item {
    id: panel
    visible: false
    property var actions: []
    signal operationPicked(int row)
    signal quickDeploy(var plan)
    signal quickRefine(var plan)

    // The rows on show: {kind: "deploy"|"action"|"op", …, hits: [indices]}.
    property var results: []
    property var plan: ({})
    // What the deploy row would do; the codename is drawn once per opening
    // so it doesn't reshuffle on every keystroke.
    property string planCodename: ""
    // Labels of actions run from here this session, most recent first.
    property var recent: []
    property var operations: []
    readonly property bool deploying: results.length > 0 && results[0].kind === "deploy"
    readonly property int rowHeight: 40

    function open() {
        planCodename = ""
        field.text = ""
        collect()
        refresh()
        visible = true
        enter.restart()
        field.forceActiveFocus()
    }
    function close() { visible = false }

    // ---- Matching ------------------------------------------------------

    function isBoundary(text, i) {
        return i === 0 || " -_/:·,.()".indexOf(text.charAt(i - 1)) >= 0
    }
    // The best placement of one token in text as a subsequence, rewarding
    // contiguous runs and word starts. null when it doesn't fit.
    function matchToken(token, text) {
        const lower = text.toLowerCase()
        let best = null
        for (let start = lower.indexOf(token[0]); start >= 0; start = lower.indexOf(token[0], start + 1)) {
            const hits = [start]
            let score = 1 + (isBoundary(text, start) ? 6 : 0) + (start === 0 ? 3 : 0)
            let run = 0
            let pos = start
            let ok = true
            for (let k = 1; k < token.length; ++k) {
                const c = token[k]
                let next = -1
                if (lower.charAt(pos + 1) === c) {
                    next = pos + 1
                } else {
                    // A later word start beats an arbitrary letter.
                    for (let j = pos + 1; j < lower.length; ++j)
                        if (lower.charAt(j) === c && isBoundary(text, j)) { next = j; break }
                    if (next < 0) next = lower.indexOf(c, pos + 1)
                }
                if (next < 0) { ok = false; break }
                if (next === pos + 1) { run += 1; score += 1 + 2 * run }
                else { run = 0; score += 1 + (isBoundary(text, next) ? 5 : 0) - Math.min(3, (next - pos - 1) * 0.5) }
                hits.push(next)
                pos = next
            }
            if (ok && (best === null || score > best.score))
                best = { score: score, hits: hits }
        }
        return best
    }
    // Every token must fit; shorter texts edge ahead.
    function score(query, text) {
        const tokens = query.toLowerCase().split(/\s+/).filter(t => t.length > 0)
        let total = 0
        let hits = []
        for (const token of tokens) {
            const m = matchToken(token, text)
            if (!m) return null
            total += m.score
            hits = hits.concat(m.hits)
        }
        if (text.toLowerCase().startsWith(query.toLowerCase())) total += 8
        return { score: total - text.length * 0.15, hits: hits }
    }

    // ---- Rows -----------------------------------------------------------

    // Operations come from a hidden Repeater over the model.
    function collect() {
        const list = []
        for (let i = 0; i < opReader.count; ++i) {
            const item = opReader.itemAt(i)
            if (!item || item.archived) continue
            const dir = item.directory.replace(/\/+$/, "")
            list.push({ row: item.index, codename: item.codename, status: item.status,
                        directory: item.directory, project: dir.substring(dir.lastIndexOf("/") + 1) })
        }
        operations = list
    }

    function actionRow(a, hits) {
        return { kind: "action", label: a.label, key: a.key || "", action: a, hits: hits || [] }
    }
    function opRow(o, hits) {
        return { kind: "op", row: o.row, codename: o.codename, status: o.status,
                 project: o.project, hits: hits || [] }
    }

    function refresh() {
        const query = field.text.trim()
        const rows = []
        if (query.length === 0) {
            // Recently run first, then the everyday ones, then operations,
            // then everything else.
            const shown = {}
            const take = a => { if (a && !shown[a.label]) { shown[a.label] = true; rows.push(actionRow(a)) } }
            for (const label of recent) take(actions.find(a => a.label === label))
            for (const key of ["N", "I", "G", "C", ","]) take(actions.find(a => a.key === key))
            for (const o of operations) rows.push(opRow(o))
            for (const a of actions) take(a)
        } else {
            const scored = []
            for (const a of actions) {
                const m = score(query, a.label)
                if (m) scored.push({ score: m.score + (recent.indexOf(a.label) >= 0 ? 2 : 0), row: actionRow(a, m.hits) })
            }
            for (const o of operations) {
                // Callsign and project as one string; split the hits back out.
                const text = o.codename + " " + o.project
                const m = score(query, text)
                if (m) scored.push({ score: m.score, row: opRow(o, m.hits) })
            }
            scored.sort((x, y) => y.score - x.score)
            const words = query.split(/\s+/).length
            const letters = query.replace(/\s+/g, "").length
            const weak = scored.length === 0 || scored[0].score < 2.5 * letters
            if (letters >= 3 && (words >= 3 || weak)) {
                const fallback = operations.length > 0 ? operations[0].directory
                               : (opReader.count > 0 && opReader.itemAt(0) ? opReader.itemAt(0).directory : "")
                const p = ops.quickPlan(query, fallback)
                if (planCodename.length === 0) planCodename = p.codename
                p.codename = planCodename
                plan = p
                rows.push({ kind: "deploy", hits: [] })
            }
            for (const s of scored.slice(0, 60)) rows.push(s.row)
        }
        results = rows
        list.currentIndex = rows.length > 0 ? 0 : -1
        list.positionViewAtBeginning()
    }

    function move(by) {
        if (list.count === 0) return
        list.currentIndex = Math.max(0, Math.min(list.count - 1, list.currentIndex + by))
    }

    function run(index, refine) {
        const row = results[index]
        if (!row) return
        if (row.kind === "deploy") {
            if (refine) panel.quickRefine(plan)
            else if (plan.directory && plan.directory.length > 0) panel.quickDeploy(plan)
        } else if (row.kind === "op") {
            panel.operationPicked(row.row)
        } else {
            recent = [row.label].concat(recent.filter(l => l !== row.label)).slice(0, 3)
            close()
            row.action.run()
        }
    }

    // Text with the matched letters inked, for StyledText.
    function marked(text, hits, from, base, ink) {
        const set = {}
        for (const h of hits) set[h - from] = true
        let out = ""
        for (let i = 0; i < text.length; ++i) {
            let c = text.charAt(i)
            c = c === "&" ? "&amp;" : c === "<" ? "&lt;" : c === ">" ? "&gt;" : c
            out += set[i] ? "<font color=\"" + ink + "\">" + c + "</font>" : c
        }
        return "<font color=\"" + base + "\">" + out + "</font>"
    }

    function basename(path) {
        const p = (path || "").replace(/\/+$/, "")
        return p.substring(p.lastIndexOf("/") + 1)
    }

    Item {
        visible: false
        Repeater {
            id: opReader
            model: ops
            delegate: Item {
                required property string codename
                required property string status
                required property string directory
                required property bool archived
                required property int index
                onStatusChanged: if (panel.visible) refreshLater.restart()
            }
            onItemAdded: if (panel.visible) refreshLater.restart()
            onItemRemoved: if (panel.visible) refreshLater.restart()
        }
    }
    Timer {
        id: refreshLater
        interval: 50
        onTriggered: {
            const at = list.currentIndex
            panel.collect()
            panel.refresh()
            list.currentIndex = Math.min(at, list.count - 1)
        }
    }

    // A small moulded key cap, as in KeyHint.
    component Cap: Rectangle {
        property string key
        implicitWidth: Math.max(20, capText.implicitWidth + 10)
        implicitHeight: 20
        color: Style.panel
        border.color: Style.lineStrong
        radius: Math.min(3, theme.radius)
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.margins: 1
            height: 1
            color: Qt.rgba(0, 0, 0, 0.4)
        }
        Text {
            id: capText
            anchors.centerIn: parent
            text: parent.key
            color: Style.text
            font.family: Style.mono
            font.variableAxes: Style.narrow
            font.pixelSize: 10
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Style.bg.r, Style.bg.g, Style.bg.b, 0.86)
        MouseArea { anchors.fill: parent; onClicked: panel.close() }
    }

    Rectangle {
        id: sheet
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(24, Math.min(110, parent.height * 0.12))
        width: Math.min(680, parent.width - 48)
        height: column.implicitHeight
        color: Style.panel
        border.color: Style.lineStrong
        radius: theme.radius
        MouseArea { anchors.fill: parent }
        Brackets { anchors.fill: parent; anchors.margins: -1; size: 12 }

        ParallelAnimation {
            id: enter
            NumberAnimation { target: sheet; property: "opacity"; from: 0; to: 1; duration: 140 }
            NumberAnimation { target: shift; property: "y"; from: 8; to: 0; duration: 140; easing.type: Easing.OutCubic }
        }
        transform: Translate { id: shift }

        ColumnLayout {
            id: column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 0

            // The field.
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 60
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                spacing: 12
                Text {
                    text: "›"
                    color: theme.accent
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 20
                    Layout.alignment: Qt.AlignVCenter
                    Layout.topMargin: -2
                }
                TextInput {
                    id: field
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    color: Style.text
                    selectionColor: Style.wash
                    selectedTextColor: Style.text
                    font.family: Style.body
                    font.pixelSize: 18
                    clip: true
                    onTextChanged: panel.refresh()
                    Text {
                        anchors.fill: parent
                        visible: field.text.length === 0
                        text: qsTr("Type a command, an operation, or a task to deploy")
                        color: Style.faint
                        font: field.font
                        elide: Text.ElideRight
                    }
                    Keys.onPressed: (event) => {
                        const ctrl = event.modifiers & Qt.ControlModifier
                        if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_J)) {
                            panel.move(1); event.accepted = true
                        } else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_K)) {
                            panel.move(-1); event.accepted = true
                        } else if (event.key === Qt.Key_PageDown) {
                            panel.move(10); event.accepted = true
                        } else if (event.key === Qt.Key_PageUp) {
                            panel.move(-10); event.accepted = true
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            const shift = event.modifiers & Qt.ShiftModifier
                            // Shift+Enter briefs the typed task whichever row is lit.
                            if (shift && panel.deploying) panel.run(0, true)
                            else panel.run(list.currentIndex, false)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
                            panel.close(); event.accepted = true
                        }
                    }
                }
            }

            Rectangle {
                visible: list.count > 0
                Layout.fillWidth: true
                implicitHeight: 1
                color: Style.lineStrong
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight,
                                                 panel.rowHeight * 10 + 6,
                                                 Math.max(panel.rowHeight * 3, panel.height - sheet.y - 140))
                Layout.topMargin: count > 0 ? 6 : 0
                Layout.bottomMargin: count > 0 ? 6 : 0
                visible: count > 0
                clip: true
                model: panel.results
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                highlightFollowsCurrentItem: false
                ScrollBar.vertical: ScrollBar { policy: list.contentHeight > list.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool current: ListView.isCurrentItem
                    readonly property string kind: modelData.kind
                    width: ListView.view.width
                    height: kind === "deploy" ? 58 : panel.rowHeight
                    color: current ? Style.wash : hover.hovered ? Style.raised : "transparent"

                    Rectangle {
                        visible: row.current
                        width: 2
                        height: parent.height
                        color: theme.accent
                    }

                    // An action: its label and key.
                    RowLayout {
                        visible: row.kind === "action"
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 12
                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            textFormat: Text.StyledText
                            text: row.kind === "action"
                                  ? panel.marked(row.modelData.label, row.modelData.hits, 0,
                                                 row.current ? Style.text : Style.text2, theme.accent)
                                  : ""
                            font.family: Style.body
                            font.pixelSize: 14
                            font.weight: Font.Medium
                        }
                        Cap {
                            visible: row.kind === "action" && row.modelData.key.length > 0
                            key: row.kind === "action" ? row.modelData.key : ""
                        }
                    }

                    // An operation: callsign, status and project.
                    RowLayout {
                        visible: row.kind === "op"
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 10
                        Text {
                            textFormat: Text.StyledText
                            text: row.kind === "op"
                                  ? panel.marked(row.modelData.codename, row.modelData.hits, 0,
                                                 row.current ? Style.text : Style.text2, theme.accent)
                                  : ""
                            font.family: Style.mono
                            font.variableAxes: Style.wide
                            font.pixelSize: 13
                            font.letterSpacing: -0.3
                        }
                        Rectangle {
                            Layout.leftMargin: 4
                            implicitWidth: 7
                            implicitHeight: 7
                            color: row.kind === "op" ? Style.statusColor(row.modelData.status, theme.accent) : "transparent"
                        }
                        Text {
                            text: row.kind === "op" ? Style.statusLabel(row.modelData.status) : ""
                            color: Style.dim
                            font.family: Style.body
                            font.pixelSize: 12
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            Layout.maximumWidth: row.width * 0.4
                            elide: Text.ElideMiddle
                            textFormat: Text.StyledText
                            text: row.kind === "op"
                                  ? panel.marked(row.modelData.project, row.modelData.hits,
                                                 row.modelData.codename.length + 1, Style.dim, theme.accent)
                                  : ""
                            font.family: Style.mono
                            font.variableAxes: Style.narrow
                            font.pixelSize: 11
                        }
                    }

                    // The quick deploy: the task, and what it'll set going.
                    RowLayout {
                        visible: row.kind === "deploy"
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 12
                        Rectangle {
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 15
                            implicitWidth: 7
                            implicitHeight: 7
                            color: theme.accent
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 4
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: row.kind === "deploy"
                                      ? qsTr("Deploy: %1").arg(panel.plan.objective || field.text.trim()) : ""
                                color: Style.text
                                font.family: Style.body
                                font.pixelSize: 14
                                font.weight: Font.Medium
                                textFormat: Text.PlainText
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                readonly property bool aimed: (panel.plan.directory || "").length > 0
                                spacing: 0
                                Text {
                                    visible: parent.aimed
                                    text: panel.plan.codename || ""
                                    color: Style.text2
                                    font.family: Style.mono
                                    font.variableAxes: Style.wide
                                    font.pixelSize: 11
                                    textFormat: Text.PlainText
                                }
                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: !parent.aimed ? qsTr("Name a project folder (~/Work/…) to deploy")
                                          : "  →  " + panel.basename(panel.plan.directory) + "  ·  " + (Prefs.defaultLoadout || "Standard")
                                    color: parent.aimed ? Style.dim : Style.amber
                                    font.family: parent.aimed ? Style.mono : Style.body
                                    font.variableAxes: parent.aimed ? Style.narrow : ({})
                                    font.pixelSize: parent.aimed ? 11 : 12
                                    textFormat: Text.PlainText
                                }
                            }
                        }
                        Cap {
                            visible: row.current
                            key: "Enter"
                            opacity: (panel.plan.directory || "").length > 0 ? 1 : 0.4
                        }
                    }

                    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: (point) => {
                            list.currentIndex = row.index
                            panel.run(row.index, point.modifiers & Qt.ShiftModifier)
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Style.line
            }

            // Keys.
            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.topMargin: 10
                Layout.bottomMargin: 10
                spacing: 18
                KeyHint { key: "↑↓"; label: qsTr("move") }
                KeyHint { key: "Enter"; label: qsTr("run") }
                KeyHint { visible: panel.deploying; key: "Shift+Enter"; label: qsTr("refine in the briefing") }
                KeyHint { key: "Esc"; label: qsTr("close") }
            }
        }
    }
}
