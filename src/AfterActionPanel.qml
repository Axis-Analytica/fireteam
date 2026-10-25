import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// The after-action report: what an operation did, start to finish, printed
// like the end of a match. The figures count up and the run timeline draws
// itself once on opening; the proof and the debrief are a click away.
Item {
    id: panel
    visible: false

    // The roster entry, live while it lives; a snapshot stands in if the
    // roster drops it while the report is open.
    property var target: null
    property int row: -1
    property var snap: ({})

    signal readRequested(string path, string title)
    signal intelRequested()
    signal replayRequested()

    // 0 → 1 on opening: the figures' count and the timeline's growth.
    property real count: 1
    property real grow: 1

    function field(key, fallback) {
        const v = target ? target[key] : snap[key]
        return v === undefined || v === null ? fallback : v
    }

    readonly property string codename: field("codename", "")
    readonly property string status: field("status", "")
    readonly property bool failed: status !== "complete"
    readonly property var history: field("history", [])
    readonly property var reviews: field("reviews", [])
    readonly property var gates: field("lastGates", [])
    readonly property var criteria: field("criteria", [])
    readonly property var reports: field("reports", [])
    readonly property string sitrep: field("sitrep", "")
    readonly property string engine: field("engine", "") || "claude"
    readonly property string model: field("model", "")
    readonly property var review: reviews.length > 0 ? reviews[reviews.length - 1] : null

    readonly property int runs: history.length
    readonly property int completeRuns: history.filter(h => h.outcome === "complete").length
    readonly property int failedRuns: history.filter(h => h.outcome === "failed").length
    readonly property int files: sum("files")
    readonly property int added: sum("added")
    readonly property int removed: sum("removed")
    readonly property int seconds: sum("seconds")
    readonly property int sessions: {
        const seen = {}
        for (const h of history) seen[h.session || 1] = true
        return Object.keys(seen).length
    }
    readonly property real cost: {
        const c = field("cost", 0)
        return c > 0 ? c : sum("cost")
    }
    // Codex and Gemini CLI don't report a cost.
    readonly property bool showCost: cost > 0 || engine === "claude" || engine === "opencode"
    readonly property int gatesPassed: gates.filter(g => g.passed).length
    readonly property int criteriaMet: criteria.filter(c => c.state === "met").length

    function sum(key) {
        let total = 0
        for (const h of history) total += Number(h[key] || 0)
        return total
    }
    function number(n) { return Math.round(n).toLocaleString(Qt.locale(), 'f', 0) }
    function money(value) { return "≈$" + Number(value || 0).toLocaleString(Qt.locale(), 'f', 2) }
    function duration(s) {
        s = Math.round(s)
        if (s < 60) return qsTr("%1s").arg(s)
        if (s < 3600) return qsTr("%1m %2s").arg(Math.floor(s / 60)).arg(Style.pad(s % 60))
        return qsTr("%1h %2m").arg(Math.floor(s / 3600)).arg(Style.pad(Math.floor(s % 3600 / 60)))
    }
    function clock(iso) {
        const d = new Date(iso)
        return isNaN(d.getTime()) ? "" : Style.pad(d.getHours()) + ":" + Style.pad(d.getMinutes())
    }
    function outcomeColor(outcome) {
        return outcome === "complete" ? theme.accent : outcome === "failed" ? Style.danger : Style.dim
    }

    // The one line that sums it up: overwatch's grade, else the gates.
    readonly property string verdict: {
        if (review) {
            const n = (review.findings || []).length
            return qsTr("Overwatch verdict: %1").arg(Style.gradeLabel(review.grade))
                   + (n > 0 ? " · " + qsTr("findings: %1").arg(n) : "")
        }
        if (gates.length > 0)
            return gatesPassed === gates.length ? qsTr("Gates passed: %1 of %2").arg(gatesPassed).arg(gates.length)
                                                : qsTr("Gates failed: %1 of %2").arg(gates.length - gatesPassed).arg(gates.length)
        return qsTr("No gates or overwatch review on record")
    }
    readonly property color verdictTone: review ? Style.gradeColor(review.grade)
                                       : gates.length > 0 ? (gatesPassed === gates.length ? Style.good : Style.danger) : Style.dim

    function open(target, row) {
        snap = target ? {
            codename: target.codename, status: target.status, history: target.history, reviews: target.reviews,
            lastGates: target.lastGates, criteria: target.criteria, reports: target.reports, sitrep: target.sitrep,
            engine: target.engine, model: target.model, cost: target.cost, opId: target.opId
        } : ({})
        panel.target = target
        panel.row = row
        visible = true
        enter.restart()
        if (Prefs.reduceMotion) {
            count = 1
            grow = 1
        } else {
            reveal.restart()
        }
    }
    function close() {
        reveal.stop()
        visible = false
    }

    ParallelAnimation {
        id: reveal
        NumberAnimation { target: panel; property: "count"; from: 0; to: 1; duration: 700; easing.type: Easing.OutCubic }
        SequentialAnimation {
            PauseAnimation { duration: 120 }
            NumberAnimation {
                target: panel; property: "grow"; from: 0; to: 1
                duration: Math.min(1600, 500 + 120 * panel.runs)
            }
        }
    }

    Material.theme: Material.Dark
    Material.accent: theme.accent

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Style.bg.r, Style.bg.g, Style.bg.b, 0.86)
        MouseArea { anchors.fill: parent; onClicked: panel.close() }
    }

    Rectangle {
        id: sheet
        property real rise: 0
        anchors.centerIn: parent
        anchors.verticalCenterOffset: rise
        width: Math.min(1120, parent.width - 48)
        height: Math.min(content.implicitHeight + footer.implicitHeight + 64 + 41, parent.height - 48)
        color: Style.panel
        border.color: Style.lineStrong
        radius: theme.radius
        MouseArea { anchors.fill: parent }
        Brackets { anchors.fill: parent; anchors.margins: -1; size: 12 }

        readonly property bool wide: width > 1000

        ParallelAnimation {
            id: enter
            NumberAnimation { target: sheet; property: "opacity"; from: 0; to: 1; duration: 140 }
            NumberAnimation { target: sheet; property: "rise"; from: 8; to: 0; duration: 180; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 32
            spacing: 0

            ScrollView {
                id: scroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                clip: true

                ColumnLayout {
                    id: content
                    width: scroll.availableWidth
                    spacing: 24

                    // Header: the eyebrow, the outcome, the callsign, the verdict.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Text {
                            Layout.fillWidth: true
                            text: "# " + qsTr("After-action").toLowerCase() + " // " + panel.codename
                            elide: Text.ElideRight
                            color: Style.dim
                            font.family: Style.mono
                            font.variableAxes: Style.narrow
                            font.pixelSize: 11
                        }
                        Text {
                            Layout.fillWidth: true
                            text: panel.failed ? qsTr("Operation failed") : qsTr("Operation complete")
                            elide: Text.ElideRight
                            color: panel.failed ? Style.danger : Style.text
                            font.family: Style.display
                            font.pixelSize: 30
                            font.weight: Font.DemiBold
                            font.letterSpacing: -0.6
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.topMargin: 6
                            Layout.preferredHeight: 64
                            text: panel.codename
                            fontSizeMode: Text.HorizontalFit
                            minimumPixelSize: 28
                            verticalAlignment: Text.AlignVCenter
                            color: Style.text
                            font.family: Style.mono
                            font.variableAxes: Style.wide
                            font.pixelSize: 56
                            font.letterSpacing: -1.2
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            spacing: 10
                            Rectangle { implicitWidth: 7; implicitHeight: 7; color: panel.verdictTone }
                            Text {
                                Layout.fillWidth: true
                                text: panel.verdict
                                elide: Text.ElideRight
                                color: Style.text2
                                font.family: Style.body
                                font.pixelSize: 14
                                font.weight: Font.Medium
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.maximumWidth: 820
                            Layout.topMargin: 2
                            visible: text.length > 0
                            text: panel.sitrep
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            color: Style.dim
                            font.family: Style.body
                            font.pixelSize: 13
                            lineHeight: 1.25
                            textFormat: Text.PlainText
                        }
                    }

                    // The figures, wide and light on a ruled band, counting up.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.lineStrong }
                        GridLayout {
                            id: figures
                            Layout.fillWidth: true
                            columns: sheet.wide ? figureModel.length : 3
                            columnSpacing: 0
                            rowSpacing: 0
                            readonly property var figureModel: {
                                const c = panel.count
                                const list = [
                                    { label: qsTr("Cycles run"), value: panel.number(panel.runs * c),
                                      note: qsTr("%1 complete · %2 failed").arg(panel.completeRuns).arg(panel.failedRuns) },
                                    { label: qsTr("Files changed"), value: panel.number(panel.files * c), note: "" },
                                    { label: qsTr("Lines changed"), value: "+" + panel.number(panel.added * c) + " −" + panel.number(panel.removed * c),
                                      note: "" },
                                    { label: qsTr("Time in the field"), value: panel.duration(panel.seconds * c), note: "" },
                                    { label: qsTr("API value"), value: panel.money(panel.cost * c), note: qsTr("API prices, not a bill"),
                                      cost: true },
                                    { label: qsTr("Sessions"), value: panel.number(panel.sessions * c),
                                      note: qsTr("%n hand-off(s)", "", Math.max(0, panel.sessions - 1)) }
                                ]
                                return list.filter(f => !f.cost || panel.showCost)
                            }
                            Repeater {
                                model: figures.figureModel.length
                                delegate: Item {
                                    required property int index
                                    readonly property var figure: figures.figureModel[index]
                                    readonly property bool firstInRow: index % figures.columns === 0
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.preferredWidth: 1
                                    implicitHeight: cell.implicitHeight + 32
                                    Rectangle { visible: !parent.firstInRow; width: 1; height: parent.height - 24; y: 12; color: Style.line }
                                    Rectangle { visible: index >= figures.columns; width: parent.width; height: 1; color: Style.line }
                                    ColumnLayout {
                                        id: cell
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.leftMargin: parent.firstInRow ? 0 : 18
                                        anchors.rightMargin: 12
                                        anchors.topMargin: 16
                                        spacing: 3
                                        Text {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 40
                                            text: figure.value
                                            fontSizeMode: Text.HorizontalFit
                                            minimumPixelSize: 16
                                            verticalAlignment: Text.AlignBottom
                                            color: Style.text
                                            font.family: Style.mono
                                            font.variableAxes: Style.figure
                                            font.pixelSize: 30
                                            font.letterSpacing: -0.8
                                            font.features: { "tnum": 1 }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: "# " + figure.label.toLowerCase()
                                            elide: Text.ElideRight
                                            color: Style.text2
                                            font.family: Style.mono
                                            font.variableAxes: Style.narrow
                                            font.pixelSize: 11
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: figure.note || " "
                                            elide: Text.ElideRight
                                            color: Style.dim
                                            font.family: Style.mono
                                            font.variableAxes: Style.narrow
                                            font.pixelSize: 10
                                        }
                                    }
                                }
                            }
                        }
                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }
                    }

                    // The run timeline: one bar per cycle, as long as it ran,
                    // coloured by how it ended, its gates in squares above.
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: panel.runs > 0
                        spacing: 12
                        SectionLabel {
                            Layout.fillWidth: true
                            text: qsTr("Run timeline")
                            detail: qsTr("%n cycle(s)", "", panel.runs) + " · " + panel.duration(panel.seconds)
                        }
                        Item {
                            id: strip
                            Layout.fillWidth: true
                            implicitHeight: 54
                            readonly property int gap: 3
                            readonly property int minWidth: 12
                            readonly property real spare: Math.max(0, width - panel.runs * minWidth - (panel.runs - 1) * gap)
                            function barWidth(i) {
                                const s = Number(panel.history[i].seconds || 0)
                                return minWidth + (panel.seconds > 0 ? spare * s / panel.seconds : spare / panel.runs)
                            }
                            // A faint track the bars grow along.
                            Rectangle { y: 16; width: parent.width; height: 14; color: Style.bg; border.color: Style.line }
                            Row {
                                spacing: strip.gap
                                Repeater {
                                    model: panel.history
                                    delegate: Item {
                                        id: bar
                                        required property var modelData
                                        required property int index
                                        readonly property var runGates: modelData.gates || []
                                        readonly property real phase: Math.max(0, Math.min(1, (panel.grow * (panel.runs + 1) - index) / 2))
                                        readonly property real eased: 1 - Math.pow(1 - phase, 3)
                                        width: strip.barWidth(index)
                                        height: strip.height
                                        // Gate squares, green or red, as many as fit.
                                        Row {
                                            spacing: 3
                                            opacity: bar.phase >= 1 ? 1 : 0
                                            Repeater {
                                                model: Math.min(bar.runGates.length, Math.max(1, Math.floor((bar.width + 3) / 9)))
                                                Rectangle {
                                                    required property int index
                                                    width: 6; height: 6
                                                    color: bar.runGates[index].passed ? Style.good : Style.danger
                                                }
                                            }
                                        }
                                        Rectangle {
                                            y: 16
                                            width: bar.width * bar.eased
                                            height: 14
                                            color: panel.outcomeColor(bar.modelData.outcome)
                                            opacity: hover.hovered ? 1 : 0.85
                                        }
                                        Rectangle {
                                            visible: hover.hovered && panel.visible
                                            y: 14; x: -2
                                            width: bar.width + 4; height: 18
                                            color: "transparent"
                                            border.color: Style.text2
                                        }
                                        Text {
                                            y: 38
                                            width: bar.width
                                            visible: bar.width >= implicitWidth
                                            text: Style.pad(bar.modelData.cycle || bar.index + 1)
                                            color: hover.hovered ? Style.text : Style.dim
                                            font.family: Style.mono
                                            font.variableAxes: Style.narrow
                                            font.pixelSize: 10
                                            font.features: { "tnum": 1 }
                                        }
                                        HoverHandler { id: hover }
                                        ToolTip {
                                            id: tip
                                            parent: bar
                                            visible: hover.hovered && panel.visible
                                            delay: 150
                                            y: -implicitHeight - 6
                                            x: Math.max(-bar.x, Math.min(0, strip.width - bar.x - width))
                                            width: Math.min(380, implicitContentWidth + leftPadding + rightPadding)
                                            padding: 10
                                            background: Rectangle { color: Style.raised; border.color: Style.lineStrong; radius: Math.min(2, theme.radius) }
                                            contentItem: Column {
                                                spacing: 4
                                                Text {
                                                    width: parent.width
                                                    text: qsTr("Cycle %1 · %2 · %3").arg(bar.modelData.cycle || bar.index + 1)
                                                              .arg(Style.statusLabel(bar.modelData.outcome)).arg(panel.duration(bar.modelData.seconds || 0))
                                                    color: panel.outcomeColor(bar.modelData.outcome)
                                                    font.family: Style.mono
                                                    font.variableAxes: Style.narrowMedium
                                                    font.pixelSize: 11
                                                }
                                                Text {
                                                    width: Math.min(360, implicitWidth)
                                                    text: bar.modelData.sitrep || qsTr("No sitrep.")
                                                    wrapMode: Text.Wrap
                                                    maximumLineCount: 8
                                                    elide: Text.ElideRight
                                                    color: Style.text2
                                                    font.family: Style.body
                                                    font.pixelSize: 12
                                                    lineHeight: 1.2
                                                    textFormat: Text.PlainText
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        // When it ran, first light to last.
                        RowLayout {
                            Layout.fillWidth: true
                            readonly property var first: panel.history.find(h => !!h.started)
                            readonly property var last: panel.history.slice().reverse().find(h => !!h.started)
                            visible: !!first
                            Text {
                                text: parent.first ? panel.clock(parent.first.started) : ""
                                color: Style.faint
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 10
                            }
                            Item { Layout.fillWidth: true }
                            Row {
                                spacing: 14
                                Repeater {
                                    model: [
                                        { tone: theme.accent, label: qsTr("Complete") },
                                        { tone: Style.danger, label: qsTr("Failed") },
                                        { tone: Style.dim, label: qsTr("Other") }
                                    ]
                                    Row {
                                        required property var modelData
                                        spacing: 6
                                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; color: modelData.tone }
                                        Text {
                                            text: modelData.label
                                            color: Style.dim
                                            font.family: Style.body
                                            font.pixelSize: 11
                                        }
                                    }
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: {
                                    const l = parent.last
                                    if (!l) return ""
                                    const d = new Date(l.started)
                                    return isNaN(d.getTime()) ? "" : panel.clock(new Date(d.getTime() + 1000 * (l.seconds || 0)).toISOString())
                                }
                                color: Style.faint
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 10
                            }
                        }
                    }

                    // Proof: the gates and the criteria; overwatch's verdict.
                    GridLayout {
                        Layout.fillWidth: true
                        columns: sheet.wide ? 2 : 1
                        columnSpacing: 40
                        rowSpacing: 24

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.alignment: Qt.AlignTop
                            spacing: 0
                            SectionLabel {
                                Layout.fillWidth: true
                                Layout.bottomMargin: 8
                                text: qsTr("Gates")
                                detail: panel.gates.length > 0 ? qsTr("%1 of %2 passed").arg(panel.gatesPassed).arg(panel.gates.length) : ""
                            }
                            Repeater {
                                model: panel.gates
                                delegate: ProofRow {
                                    required property var modelData
                                    tone: modelData.passed ? Style.good : Style.danger
                                    title: modelData.name || ""
                                    meta: modelData.command || ""
                                    mark: modelData.passed ? qsTr("Passed") : qsTr("Failed")
                                }
                            }
                            Empty { visible: panel.gates.length === 0; text: qsTr("No gates ran.") }

                            SectionLabel {
                                Layout.fillWidth: true
                                Layout.topMargin: 20
                                Layout.bottomMargin: 8
                                text: qsTr("Criteria")
                                detail: panel.criteria.length > 0 ? qsTr("%1 of %2 met").arg(panel.criteriaMet).arg(panel.criteria.length) : ""
                            }
                            Repeater {
                                model: panel.criteria
                                delegate: ProofRow {
                                    required property var modelData
                                    tone: modelData.state === "met" ? Style.good : modelData.state === "unmet" ? Style.danger
                                        : modelData.state === "claimed" ? Style.amber : Style.faint
                                    title: modelData.text || ""
                                    wrap: true
                                    mark: modelData.state === "met" ? qsTr("Met") : modelData.state === "unmet" ? qsTr("Not met")
                                         : modelData.state === "claimed" ? qsTr("Claimed") : qsTr("Open")
                                }
                            }
                            Empty { visible: panel.criteria.length === 0; text: qsTr("No acceptance criteria set.") }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.alignment: Qt.AlignTop
                            spacing: 10
                            SectionLabel {
                                Layout.fillWidth: true
                                text: qsTr("Overwatch")
                                detail: panel.review ? qsTr("cycle %1").arg(panel.review.cycle) : ""
                            }
                            RowLayout {
                                visible: panel.review !== null
                                Layout.fillWidth: true
                                spacing: 14
                                Chip {
                                    text: panel.review ? Style.gradeLabel(panel.review.grade) : ""
                                    tone: panel.review ? Style.gradeColor(panel.review.grade) : Style.dim
                                    marked: true
                                }
                                Text {
                                    readonly property var findings: panel.review && panel.review.findings ? panel.review.findings : []
                                    visible: findings.length > 0
                                    text: qsTr("findings: %1").arg(findings.length)
                                          + (findings.some(f => f.severity === "high") ? " · " + qsTr("high: %1").arg(findings.filter(f => f.severity === "high").length) : "")
                                    color: Style.dim
                                    font.family: Style.mono
                                    font.variableAxes: Style.narrow
                                    font.pixelSize: 11
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: qsTr("Read the review") + "  →"
                                    color: reviewHover.hovered ? Style.text : theme.accent
                                    font.family: Style.body
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    HoverHandler { id: reviewHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler {
                                        onTapped: panel.readRequested(panel.review.file,
                                                                      qsTr("%1 · overwatch review, cycle %2").arg(panel.codename).arg(panel.review.cycle))
                                    }
                                }
                            }
                            Text {
                                visible: panel.review !== null && !!panel.review.summary
                                Layout.fillWidth: true
                                text: panel.review ? panel.review.summary || "" : ""
                                wrapMode: Text.Wrap
                                maximumLineCount: 7
                                elide: Text.ElideRight
                                color: Style.text2
                                font.family: Style.body
                                font.pixelSize: 13
                                lineHeight: 1.3
                                textFormat: Text.PlainText
                            }
                            Empty { visible: panel.review === null; text: qsTr("No overwatch review on record.") }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.topMargin: 20; implicitHeight: 1; color: Style.line }

            RowLayout {
                id: footer
                Layout.fillWidth: true
                Layout.topMargin: 20
                spacing: 10
                Text {
                    Layout.fillWidth: true
                    text: "# " + [panel.field("opId", ""), panel.engine, panel.model].filter(s => s.length > 0).join(" · ")
                    elide: Text.ElideRight
                    color: Style.faint
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 11
                }
                TacticalButton { text: qsTr("Close"); key: "Esc"; onClicked: panel.close() }
                TacticalButton { text: qsTr("Replay"); enabled: panel.runs > 0; onClicked: panel.replayRequested() }
                TacticalButton { text: qsTr("Intel"); onClicked: panel.intelRequested() }
                TacticalButton {
                    text: qsTr("Read the last debrief")
                    primary: true
                    enabled: panel.reports.length > 0
                    onClicked: panel.readRequested(panel.reports[panel.reports.length - 1],
                                                   qsTr("%1 · cycle %2 debrief").arg(panel.codename).arg(panel.reports.length))
                }
            }
        }
    }

    // A proof row: a square in the state's colour, the name, a mono note and
    // the state, over a hairline.
    component ProofRow: Item {
        id: proof
        property color tone: Style.dim
        property string title
        property string meta
        property string mark
        property bool wrap: false
        Layout.fillWidth: true
        implicitHeight: proofRow.implicitHeight + 16
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Style.line }
        RowLayout {
            id: proofRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Rectangle {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 6
                implicitWidth: 7; implicitHeight: 7
                color: proof.tone
            }
            Text {
                Layout.fillWidth: proof.meta.length === 0
                Layout.maximumWidth: proof.wrap ? -1 : implicitWidth
                text: proof.title
                wrapMode: proof.wrap ? Text.Wrap : Text.NoWrap
                elide: Text.ElideRight
                color: Style.text
                font.family: Style.body
                font.pixelSize: 13
                font.weight: proof.wrap ? Font.Normal : Font.Medium
                textFormat: Text.PlainText
            }
            Text {
                Layout.fillWidth: true
                visible: proof.meta.length > 0
                text: proof.meta
                elide: Text.ElideMiddle
                color: Style.dim
                font.family: Style.mono
                font.variableAxes: Style.narrow
                font.pixelSize: 11
            }
            Text {
                Layout.alignment: Qt.AlignTop
                text: proof.mark
                color: proof.tone === Style.faint ? Style.dim : proof.tone
                font.family: Style.body
                font.pixelSize: 12
            }
        }
    }

    component Empty: Text {
        Layout.fillWidth: true
        Layout.topMargin: 4
        wrapMode: Text.Wrap
        color: Style.faint
        font.family: Style.body
        font.pixelSize: 12
    }
}
