import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import "highlight.js" as Hl

// What one cycle changed: its files on the left, the selected file's diff on
// the right, read from the snapshots taken around the cycle.
Item {
    id: view
    visible: false
    property var op: null
    property int row: -1
    property int run: -1
    property var files: []
    property int fileIndex: 0
    property var lines: []
    // The gate whose output replaces the diff, by name, or "".
    property string gateOutput: ""
    readonly property var gateLines: {
        if (!entry || gateOutput === "") return []
        const gate = (entry.gates || []).find(g => g.name === gateOutput)
        return gate ? ("$ " + gate.command + "\n" + gate.output).split("\n") : []
    }
    readonly property var entry: op && run >= 0 && run < op.history.length ? op.history[run] : null
    readonly property bool hasIntel: entry !== null && entry.before.length > 0 && entry.after.length > 0
    // Old and new line numbers for each diff line, read from the hunk heads,
    // for the gutter.
    readonly property var numbers: {
        const out = []
        let a = 0, b = 0
        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i]
            const hunk = /^@@ -(\d+)(?:,\d+)? \+(\d+)/.exec(line)
            if (hunk) { a = parseInt(hunk[1]); b = parseInt(hunk[2]); out.push(["", ""]); continue }
            if ((a === 0 && b === 0) || (line === "" && i === lines.length - 1)) { out.push(["", ""]); continue }
            if (line.startsWith("+") && !line.startsWith("+++")) out.push(["", "" + b++])
            else if (line.startsWith("-") && !line.startsWith("---")) out.push(["" + a++, ""])
            else if (line.startsWith("\\")) out.push(["", ""])
            else out.push(["" + a++, "" + b++])
        }
        return out
    }
    // Long diffs are cut here; the full diff is a git command away.
    readonly property int lineLimit: 4000

    // Old on the left and new on the right, rather than one column.
    property bool sideBySide: false
    readonly property bool sideShown: sideBySide && gateOutput === ""
    // The list on show, for paging and the change strip.
    readonly property ListView list: sideShown ? sideDiff : diff

    // Syntax tokens for each diff line (null where the line isn't code), from
    // highlight.js, worked out once per file.
    property var tokens: []
    // The accent let down toward the ground, as an opaque colour.
    function accentAt(strength) {
        const a = Qt.color(theme.accent)
        return "" + Qt.tint(Style.bg, Qt.rgba(a.r, a.g, a.b, strength))
    }
    // The colours a token takes on each kind of line, in one hue family:
    // keywords in ink and the medium cut, strings a dimmer accent, comments
    // faint and italic, numbers secondary. Removed lines stay dim.
    readonly property var palettes: ({
        "same": { keyword: "" + Style.text, string: view.accentAt(0.78),
                  comment: "" + Style.faint, number: "" + Style.text2 },
        "add": { keyword: "" + Style.text, string: view.accentAt(0.88),
                 comment: "" + Style.faint, number: "" + Style.text2 },
        "del": { keyword: "" + Style.dim, string: view.accentAt(0.5),
                 comment: "" + Style.faint, number: "" }
    })

    // A diff line's kind: hunk heads, the file header, git's meta lines, and
    // added, removed or unchanged lines.
    function kindOf(line) {
        return line.startsWith("@@") ? "hunk"
            : line.startsWith("+++") ? "head"
            : line.startsWith("---") || line.startsWith("diff ") || line.startsWith("index ")
              || line.startsWith("new file") || line.startsWith("deleted file") ? "meta"
            : line.startsWith("+") ? "add"
            : line.startsWith("-") ? "del" : "same"
    }
    function stateKey(state) { return state ? state.close : "" }
    function highlight(all, path) {
        const lang = Hl.language(path)
        const out = new Array(all.length).fill(null)
        if (lang === "") return out
        // The old file and the new one each carry their own open comment or
        // string from line to line; a hunk head starts both afresh.
        let before = null, after = null
        for (let i = 0; i < all.length; ++i) {
            const line = all[i]
            const kind = kindOf(line)
            if (kind === "hunk") { before = after = null; continue }
            if (kind === "add") {
                const r = Hl.tokenize(line.substring(1), lang, after)
                out[i] = r.tokens; after = r.state
            } else if (kind === "del") {
                const r = Hl.tokenize(line.substring(1), lang, before)
                out[i] = r.tokens; before = r.state
            } else if (kind === "same" && line.startsWith(" ")) {
                const body = line.substring(1)
                const r = Hl.tokenize(body, lang, after)
                out[i] = r.tokens
                before = stateKey(before) === stateKey(after) ? r.state : Hl.tokenize(body, lang, before).state
                after = r.state
            }
        }
        return out
    }

    // The side-by-side rows: unchanged lines on both sides, each run of
    // removed lines paired with the added run after it, and hunk heads and
    // git's meta lines across the width. l and r are line indexes (-1 for
    // none); full is a line shown across both columns.
    readonly property var rows: {
        const out = []
        let dels = [], adds = []
        const flush = () => {
            for (let k = 0; k < Math.max(dels.length, adds.length); ++k)
                out.push({ l: k < dels.length ? dels[k] : -1, r: k < adds.length ? adds[k] : -1, full: -1 })
            dels = []; adds = []
        }
        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i]
            const kind = kindOf(line)
            if (kind === "del") { if (adds.length > 0) flush(); dels.push(i); continue }
            if (kind === "add") { adds.push(i); continue }
            flush()
            if (line === "" && i === lines.length - 1) continue
            if (kind === "same" && line.startsWith(" ") && numbers[i] && numbers[i][0] !== "")
                out.push({ l: i, r: i, full: -1 })
            else
                out.push({ l: -1, r: -1, full: i })
        }
        flush()
        return out
    }
    // The first line a row shows, and the row showing a line, for keeping
    // the place when switching layouts.
    function rowLine(r) { return r.full >= 0 ? r.full : r.l >= 0 ? r.l : r.r }
    function rowOf(line) {
        for (let k = 0; k < rows.length; ++k)
            if (Math.max(rows[k].full, rows[k].l, rows[k].r) >= line) return k
        return rows.length - 1
    }
    function toggleSides() {
        if (gateOutput !== "") return
        const top = list.indexAt(20, list.contentY + 2)
        const line = top < 0 ? -1 : sideShown ? (top < rows.length ? rowLine(rows[top]) : -1) : top
        sideBySide = !sideBySide
        if (line >= 0) list.positionViewAtIndex(sideShown ? rowOf(line) : line, ListView.Beginning)
    }

    // Where the changes are, for the strip beside the diff: runs of added
    // lines (lane 1) and removed ones (lane 0) over the items on show.
    readonly property int markCount: gateOutput !== "" ? 0 : sideShown ? rows.length : lines.length
    readonly property var marks: {
        const out = []
        if (markCount === 0) return out
        const open = [null, null]
        for (let k = 0; k <= markCount; ++k) {
            let del = false, add = false
            if (k < markCount) {
                if (sideShown) { del = rows[k].l >= 0 && rows[k].l !== rows[k].r; add = rows[k].r >= 0 && rows[k].l !== rows[k].r }
                else { const kind = kindOf(lines[k]); del = kind === "del"; add = kind === "add" }
            }
            const lane = [del, add]
            for (let s = 0; s < 2; ++s) {
                if (lane[s] && !open[s]) open[s] = { lane: s, from: k, count: 0 }
                if (lane[s]) open[s].count++
                else if (open[s]) { out.push(open[s]); open[s] = null }
            }
        }
        return out
    }
    function jumpToChange(fraction) {
        if (markCount === 0 || marks.length === 0) return
        const at = Math.floor(fraction * markCount)
        // Inside a change, go to that spot in it; otherwise to the start of
        // the nearest one, with a little context above.
        let best = marks[0], gap = Infinity
        for (const m of marks) {
            const d = at < m.from ? m.from - at : at >= m.from + m.count ? at - (m.from + m.count - 1) : 0
            if (d < gap) { gap = d; best = m }
        }
        if (gap === 0 && at - best.from > 3) list.positionViewAtIndex(at, ListView.Center)
        else list.positionViewAtIndex(Math.max(0, best.from - 3), ListView.Beginning)
    }

    // Each file's share of the cycle's changed lines, for the file list.
    readonly property int changedTotal: {
        let n = 0
        for (const f of files) if (!f.binary) n += (f.added || 0) + (f.removed || 0)
        return n
    }

    signal rollbackRequested(int run)

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius

    function open(target, targetRow, targetRun) {
        op = target
        row = targetRow
        visible = true
        enter.restart()
        show(targetRun)
    }
    function show(targetRun) {
        if (!op || targetRun < 0 || targetRun >= op.history.length)
            return
        run = targetRun
        gateOutput = ""
        files = ops.cycleChanges(row, run)
        pick(0)
    }
    function pick(index) {
        fileIndex = Math.max(0, Math.min(files.length - 1, index))
        if (files.length === 0) {
            tokens = []
            lines = []
            return
        }
        const all = ops.cycleDiff(row, run, files[fileIndex].path).split("\n")
        const shown = all.length > lineLimit ? all.slice(0, lineLimit).concat([qsTr("… %1 more lines").arg(all.length - lineLimit)]) : all
        tokens = files[fileIndex].binary ? [] : highlight(shown, files[fileIndex].path)
        lines = shown
        diff.positionViewAtBeginning()
        sideDiff.positionViewAtBeginning()
        fileList.positionViewAtIndex(fileIndex, ListView.Contain)
    }
    function close() { visible = false }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Style.bg.r, Style.bg.g, Style.bg.b, 0.86)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: view.close() }
    }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(1280, parent.width - 48)
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
            NumberAnimation { target: sheet; property: "anchors.verticalCenterOffset"; from: 8; to: 0; duration: 140; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // The cycle, the proof gathered for it, and its sitrep.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 28
                Layout.rightMargin: 28
                Layout.topMargin: 24
                Layout.bottomMargin: 18
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 18
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Text {
                            Layout.fillWidth: true
                            text: view.op ? "# " + qsTr("Intel // %1").arg(view.op.codename) : ""
                            elide: Text.ElideRight
                            color: Style.dim
                            font.family: Style.mono
                            font.variableAxes: Style.narrow
                            font.pixelSize: 11
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 16
                            Text {
                                text: view.entry ? qsTr("Cycle %1").arg(Style.pad(view.entry.cycle)) : ""
                                color: Style.text
                                font.family: Style.display
                                font.pixelSize: 28
                                font.weight: Font.DemiBold
                                font.letterSpacing: -0.6
                            }
                            Text {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignBaseline
                                text: !view.entry ? ""
                                    : qsTr("Run %1 of %2 · session %3 · %n file(s)", "", view.files.length)
                                          .arg(view.run + 1).arg(view.op.history.length).arg(view.entry.session)
                                      + (view.hasIntel ? "  <font color=\"" + theme.accent + "\">+" + view.entry.added
                                                         + "</font> −" + view.entry.removed : "")
                                textFormat: Text.StyledText
                                elide: Text.ElideRight
                                color: Style.dim
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 11
                            }
                        }
                    }
                    TacticalButton {
                        text: view.sideBySide ? qsTr("Unified") : qsTr("Side by side")
                        key: "S"
                        visible: view.hasIntel && view.files.length > 0
                        enabled: view.gateOutput === ""
                        onClicked: view.toggleSides()
                    }
                    TacticalButton { text: "◂"; key: "["; enabled: view.run > 0; onClicked: view.show(view.run - 1) }
                    TacticalButton {
                        text: "▸"; key: "]"
                        enabled: view.op && view.run < view.op.history.length - 1
                        onClicked: view.show(view.run + 1)
                    }
                }

                // Proof for this run: each gate (click for its output) and the
                // preview screenshot.
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: view.entry !== null && ((view.entry.gates || []).length > 0 || view.entry.screenshot !== undefined)
                    Repeater {
                        model: view.entry ? (view.entry.gates || []) : []
                        delegate: Rectangle {
                            id: gatePill
                            required property var modelData
                            readonly property bool shown: view.gateOutput === modelData.name
                            width: gateLabel.implicitWidth + 38
                            height: 28
                            color: shown ? Style.wash : gateHover.hovered ? Style.raised : Style.panel
                            border.color: shown ? theme.accent : Style.line
                            radius: Math.min(2, theme.radius)
                            Rectangle {
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: 6; height: 6
                                color: gatePill.modelData.passed ? Style.good : Style.danger
                            }
                            Text {
                                id: gateLabel
                                x: 26
                                anchors.verticalCenter: parent.verticalCenter
                                text: gatePill.modelData.name + "  <font color=\"" + Style.dim + "\">" + gatePill.modelData.seconds + "s</font>"
                                textFormat: Text.StyledText
                                color: gatePill.shown ? Style.text : Style.text2
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 11
                            }
                            HoverHandler { id: gateHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: view.gateOutput = gatePill.shown ? "" : gatePill.modelData.name }
                        }
                    }
                    TacticalButton {
                        height: 28
                        visible: view.entry !== null && view.entry.screenshot !== undefined
                        text: qsTr("Screenshot ↗")
                        onClicked: ops.openReport(view.entry.screenshot)
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: view.entry !== null && view.entry.sitrep.length > 0
                    text: view.entry ? view.entry.sitrep : ""
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    color: Style.text2
                    font.family: Style.body
                    font.pixelSize: 13
                    lineHeight: 1.15
                    textFormat: Text.PlainText
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 28
                Layout.topMargin: 18
                Layout.bottomMargin: 18
                spacing: 16
                visible: (view.hasIntel && view.files.length > 0) || view.gateOutput !== ""

                ListView {
                    id: fileList
                    Layout.preferredWidth: Math.min(340, sheet.width * 0.3)
                    Layout.fillHeight: true
                    clip: true
                    model: view.files
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}
                    delegate: Item {
                        id: fileRow
                        required property var modelData
                        required property int index
                        readonly property bool chosen: index === view.fileIndex
                        width: ListView.view.width - 10
                        height: 36
                        Rectangle {
                            anchors.fill: parent
                            color: fileRow.chosen ? Style.wash : fileHover.hovered ? Style.raised : "transparent"
                        }
                        Rectangle { visible: fileRow.chosen; width: 2; height: parent.height; color: theme.accent }
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width; height: 1
                            color: Style.line
                        }
                        // The file's share of the cycle's changed lines: added
                        // in accent, removed dim, along the foot of the row.
                        Row {
                            id: heat
                            readonly property real span: parent.width - 20
                            readonly property real share: view.changedTotal > 0 ? span / view.changedTotal : 0
                            x: 12
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 5
                            visible: !fileRow.modelData.binary
                            Rectangle {
                                width: fileRow.modelData.added > 0 ? Math.max(1, Math.round(fileRow.modelData.added * heat.share)) : 0
                                height: 2
                                color: theme.accent
                            }
                            Rectangle {
                                width: fileRow.modelData.removed > 0 ? Math.max(1, Math.round(fileRow.modelData.removed * heat.share)) : 0
                                height: 2
                                color: Style.dim
                            }
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 8
                            anchors.bottomMargin: 4
                            spacing: 10
                            Text {
                                text: fileRow.modelData.status
                                color: fileRow.modelData.status === "A" ? theme.accent
                                     : fileRow.modelData.status === "D" ? Style.dim : Style.text2
                                font.family: Style.mono
                                font.variableAxes: Style.narrowMedium
                                font.pixelSize: 11
                            }
                            Text {
                                Layout.fillWidth: true
                                text: fileRow.modelData.path
                                elide: Text.ElideMiddle
                                color: fileRow.chosen ? Style.text : Style.text2
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 12
                            }
                            Text {
                                text: fileRow.modelData.binary ? qsTr("bin")
                                    : "<font color=\"" + theme.accent + "\">+" + fileRow.modelData.added + "</font> −" + fileRow.modelData.removed
                                textFormat: Text.StyledText
                                color: Style.dim
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 11
                                font.features: { "tnum": 1 }
                            }
                        }
                        HoverHandler { id: fileHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: view.pick(fileRow.index) }
                    }
                }

                // The diff, as Terminal draws one: a gutter of line numbers, a
                // marker column, removed lines dimmed, added ones on the wash.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Style.bg
                    border.color: Style.line
                    radius: Math.min(2, theme.radius)
                    TextMetrics {
                        id: digit
                        text: "0000"
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                        font.pixelSize: 11
                    }
                    ListView {
                        id: diff
                        anchors.fill: parent
                        anchors.margins: 1
                        anchors.topMargin: 8
                        anchors.bottomMargin: 8
                        anchors.rightMargin: strip.visible ? strip.width + 10 : 1
                        visible: !view.sideShown
                        clip: true
                        model: view.gateOutput !== "" ? view.gateLines : view.lines
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {}
                        delegate: Rectangle {
                            id: diffLine
                            required property string modelData
                            required property int index
                            readonly property bool gate: view.gateOutput !== ""
                            readonly property string kind: gate ? (index === 0 ? "command" : "same") : view.kindOf(modelData)
                            readonly property var tokens: !gate && index < view.tokens.length ? view.tokens[index] : null
                            readonly property bool marked: kind === "add" || kind === "del" || kind === "command"
                                || (kind === "same" && !gate && modelData.startsWith(" "))
                            readonly property var number: !gate && index < view.numbers.length ? view.numbers[index] : ["", ""]
                            readonly property real gutter: gate ? 0 : digit.width * 2 + 28
                            width: ListView.view.width - 10
                            height: lineText.implicitHeight + (kind === "head" ? 8 : kind === "hunk" ? 10 : 2)
                            color: kind === "add" ? Style.wash : kind === "hunk" ? Style.panel : "transparent"
                            // The file header stands over a firmer line.
                            Rectangle {
                                visible: diffLine.kind === "head"
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 3
                                x: 8
                                width: parent.width - 16
                                height: 1
                                color: Style.lineStrong
                            }
                            Text {
                                visible: !diffLine.gate
                                x: 8
                                width: digit.width
                                y: lineText.y
                                horizontalAlignment: Text.AlignRight
                                text: diffLine.number[0]
                                color: Style.faint
                                font: digit.font
                            }
                            Text {
                                visible: !diffLine.gate
                                x: 8 + digit.width + 8
                                width: digit.width
                                y: lineText.y
                                horizontalAlignment: Text.AlignRight
                                text: diffLine.number[1]
                                color: Style.faint
                                font: digit.font
                            }
                            Text {
                                id: marker
                                x: diffLine.gutter + 8
                                y: lineText.y
                                text: diffLine.kind === "add" ? "+" : diffLine.kind === "del" ? "-" : diffLine.kind === "command" ? "$" : ""
                                color: diffLine.kind === "del" ? Style.dim : theme.accent
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 12
                            }
                            Text {
                                id: lineText
                                x: diffLine.gutter + 24
                                y: diffLine.kind === "hunk" ? 5 : diffLine.kind === "head" ? 0 : 1
                                width: parent.width - x - 8
                                text: {
                                    if (diffLine.tokens)
                                        return Hl.render(diffLine.tokens, view.palettes[diffLine.kind] || view.palettes.same, 1)
                                    const body = diffLine.marked && !diffLine.gate ? diffLine.modelData.substring(1)
                                               : diffLine.kind === "command" ? diffLine.modelData.replace(/^\$ /, "")
                                               : diffLine.modelData
                                    return body.length > 0 ? body : " "
                                }
                                wrapMode: Text.WrapAnywhere
                                textFormat: diffLine.tokens ? Text.StyledText : Text.PlainText
                                color: diffLine.kind === "add" || diffLine.kind === "head" || diffLine.kind === "command" ? Style.text
                                     : diffLine.kind === "del" || diffLine.kind === "hunk" ? Style.dim
                                     : diffLine.kind === "meta" ? Style.faint : Style.text2
                                font.family: Style.mono
                                font.variableAxes: diffLine.kind === "head" ? Style.narrowMedium : Style.narrow
                                font.pixelSize: 12
                            }
                            // The keywords again, in the medium cut, over the line.
                            Text {
                                visible: diffLine.tokens !== null && Hl.hasKeywords(diffLine.tokens)
                                x: lineText.x
                                y: lineText.y
                                width: lineText.width
                                text: visible ? Hl.render(diffLine.tokens, view.palettes[diffLine.kind] || view.palettes.same, 2) : ""
                                wrapMode: Text.WrapAnywhere
                                textFormat: Text.StyledText
                                color: "transparent"
                                font.family: Style.mono
                                font.variableAxes: Style.narrowMedium
                                font.pixelSize: 12
                            }
                        }
                    }
                    // Side by side: the old file on the left and the new one
                    // on the right, unchanged lines level, each removed run
                    // beside the added run that replaced it.
                    Component {
                        id: sideCell
                        Rectangle {
                            id: cell
                            readonly property int line: parent ? parent.line : -1
                            readonly property bool old: parent ? parent.old : true
                            readonly property string source: line >= 0 && line < view.lines.length ? view.lines[line] : ""
                            readonly property string kind: line < 0 ? "none" : view.kindOf(source)
                            readonly property var tokens: line >= 0 && line < view.tokens.length ? view.tokens[line] : null
                            implicitHeight: line < 0 ? 0 : code.implicitHeight + 2
                            // Where one side has no line, the well steps back.
                            color: kind === "add" ? Style.wash : kind === "none" ? Style.panel : "transparent"
                            Text {
                                x: 8
                                width: digit.width
                                y: code.y
                                horizontalAlignment: Text.AlignRight
                                text: cell.line >= 0 && cell.line < view.numbers.length ? view.numbers[cell.line][cell.old ? 0 : 1] : ""
                                color: Style.faint
                                font: digit.font
                            }
                            Text {
                                x: digit.width + 16
                                y: code.y
                                text: cell.kind === "add" ? "+" : cell.kind === "del" ? "-" : ""
                                color: cell.kind === "del" ? Style.dim : theme.accent
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 12
                            }
                            Text {
                                id: code
                                visible: cell.line >= 0
                                x: digit.width + 30
                                y: 1
                                width: parent.width - x - 8
                                text: cell.tokens ? Hl.render(cell.tokens, view.palettes[cell.kind] || view.palettes.same, 1)
                                    : Hl.plain(cell.source.substring(1))
                                wrapMode: Text.WrapAnywhere
                                textFormat: Text.StyledText
                                color: cell.kind === "add" ? Style.text : cell.kind === "del" ? Style.dim : Style.text2
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 12
                            }
                            Text {
                                visible: cell.tokens !== null && Hl.hasKeywords(cell.tokens)
                                x: code.x
                                y: code.y
                                width: code.width
                                text: visible ? Hl.render(cell.tokens, view.palettes[cell.kind] || view.palettes.same, 2) : ""
                                wrapMode: Text.WrapAnywhere
                                textFormat: Text.StyledText
                                color: "transparent"
                                font.family: Style.mono
                                font.variableAxes: Style.narrowMedium
                                font.pixelSize: 12
                            }
                        }
                    }
                    ListView {
                        id: sideDiff
                        anchors.fill: parent
                        anchors.margins: 1
                        anchors.topMargin: 8
                        anchors.bottomMargin: 8
                        anchors.rightMargin: strip.visible ? strip.width + 10 : 1
                        visible: view.sideShown
                        clip: true
                        model: view.sideShown ? view.rows : []
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {}
                        delegate: Item {
                            id: sideRow
                            required property var modelData
                            required property int index
                            readonly property bool full: modelData.full >= 0
                            readonly property string fullText: full && modelData.full < view.lines.length ? view.lines[modelData.full] : ""
                            readonly property string fullKind: full ? view.kindOf(fullText) : ""
                            readonly property real half: Math.floor((width - 1) / 2)
                            width: ListView.view.width - 10
                            height: full ? fullLine.implicitHeight + (fullKind === "head" ? 8 : fullKind === "hunk" ? 10 : 2)
                                         : Math.max(leftCell.implicitHeight, rightCell.implicitHeight)
                            Rectangle {
                                visible: sideRow.fullKind === "hunk"
                                anchors.fill: parent
                                color: Style.panel
                            }
                            Rectangle {
                                visible: sideRow.fullKind === "head"
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 3
                                x: 8
                                width: parent.width - 16
                                height: 1
                                color: Style.lineStrong
                            }
                            Text {
                                id: fullLine
                                visible: sideRow.full
                                x: digit.width + 30
                                y: sideRow.fullKind === "hunk" ? 5 : sideRow.fullKind === "head" ? 0 : 1
                                width: parent.width - x - 8
                                text: sideRow.fullText.length > 0 ? sideRow.fullText : " "
                                wrapMode: Text.WrapAnywhere
                                textFormat: Text.PlainText
                                color: sideRow.fullKind === "head" ? Style.text
                                     : sideRow.fullKind === "hunk" ? Style.dim
                                     : sideRow.fullKind === "meta" ? Style.faint : Style.text2
                                font.family: Style.mono
                                font.variableAxes: sideRow.fullKind === "head" ? Style.narrowMedium : Style.narrow
                                font.pixelSize: 12
                            }
                            Loader {
                                id: leftCell
                                readonly property int line: sideRow.modelData.l
                                readonly property bool old: true
                                active: !sideRow.full
                                width: sideRow.half
                                height: parent.height
                                sourceComponent: sideCell
                            }
                            Rectangle {
                                visible: !sideRow.full
                                x: sideRow.half
                                width: 1
                                height: parent.height
                                color: Style.line
                            }
                            Loader {
                                id: rightCell
                                readonly property int line: sideRow.modelData.r
                                readonly property bool old: false
                                active: !sideRow.full
                                x: sideRow.half + 1
                                width: parent.width - x
                                height: parent.height
                                sourceComponent: sideCell
                            }
                        }
                    }
                    // Where in the file the changes are: removed runs in the
                    // left lane, added in the right, and a frame for what's on
                    // screen. Click to jump to the nearest change.
                    Item {
                        id: strip
                        visible: view.markCount > 0 && view.marks.length > 0
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.margins: 1
                        anchors.topMargin: 8
                        anchors.bottomMargin: 8
                        anchors.rightMargin: 4
                        width: 9
                        readonly property ListView target: view.list
                        // A short diff maps onto the height it fills, so the
                        // marks sit beside their lines.
                        readonly property real span: target.contentHeight > 0 && target.contentHeight < height ? target.contentHeight : height
                        Rectangle {
                            x: 4
                            width: 1
                            height: strip.span
                            color: Style.line
                        }
                        Repeater {
                            model: strip.visible ? view.marks : []
                            delegate: Rectangle {
                                required property var modelData
                                x: modelData.lane === 0 ? 0 : 5
                                y: Math.min(strip.span - height, modelData.from / view.markCount * strip.span)
                                width: 4
                                height: Math.max(2, modelData.count / view.markCount * strip.span)
                                color: modelData.lane === 0 ? Style.dim : theme.accent
                            }
                        }
                        Rectangle {
                            id: seen
                            readonly property int first: {
                                strip.target.contentY; strip.target.height; strip.target.count
                                return Math.max(0, strip.target.indexAt(20, strip.target.contentY + 1))
                            }
                            readonly property int last: {
                                strip.target.contentY; strip.target.height; strip.target.count
                                const i = strip.target.indexAt(20, strip.target.contentY + strip.target.height - 1)
                                return i < 0 ? view.markCount - 1 : i
                            }
                            visible: strip.target.contentHeight > strip.target.height
                            x: -2
                            width: parent.width + 4
                            y: first / Math.max(1, view.markCount) * strip.span
                            height: Math.max(4, (last - first + 1) / Math.max(1, view.markCount) * strip.span)
                            color: "transparent"
                            border.color: Style.lineStrong
                        }
                        MouseArea {
                            x: -3
                            width: parent.width + 6
                            height: strip.span
                            cursorShape: Qt.PointingHandCursor
                            onPressed: (mouse) => view.jumpToChange(Math.max(0, Math.min(0.9999, mouse.y / strip.span)))
                        }
                    }
                }
            }

            // Nothing to diff: say why.
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !(view.hasIntel && view.files.length > 0) && view.gateOutput === ""
                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(560, parent.width - 48)
                    spacing: 10
                    Crosshair { Layout.alignment: Qt.AlignHCenter }
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        horizontalAlignment: Text.AlignHCenter
                        text: view.hasIntel ? qsTr("No files changed this cycle") : qsTr("No intel for this cycle")
                        wrapMode: Text.Wrap
                        color: Style.text
                        font.family: Style.display
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                        font.letterSpacing: -0.3
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        visible: !view.hasIntel
                        text: qsTr("Fireteam snapshots cycles in git repositories. Run git init in the project to get diffs and rollback.")
                        wrapMode: Text.Wrap
                        color: Style.text2
                        font.family: Style.body
                        font.pixelSize: 13
                        lineHeight: 1.15
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 28
                Layout.rightMargin: 28
                Layout.topMargin: 14
                Layout.bottomMargin: 14
                spacing: 14
                TacticalButton { text: qsTr("Close"); key: "Esc"; onClicked: view.close() }
                KeyHint { key: "J K"; label: qsTr("Files") }
                KeyHint { key: "[ ]"; label: qsTr("Cycles") }
                Item { Layout.fillWidth: true }
                TacticalButton {
                    visible: view.op !== null && view.op.canUndoRollback
                    text: qsTr("Undo rollback")
                    enabled: view.op !== null && view.op.status !== "deployed"
                    onClicked: ops.undoRollback(view.row)
                }
                TacticalButton {
                    text: view.entry ? qsTr("Roll back to before cycle %1").arg(view.entry.cycle) : ""
                    danger: true
                    enabled: view.hasIntel && view.op.status !== "deployed"
                    onClicked: view.rollbackRequested(view.run)
                }
            }
        }
    }

    Shortcut { enabled: view.visible; sequences: ["J", "Down"]; context: Qt.ApplicationShortcut; onActivated: view.pick(view.fileIndex + 1) }
    Shortcut { enabled: view.visible; sequences: ["K", "Up"]; context: Qt.ApplicationShortcut; onActivated: view.pick(view.fileIndex - 1) }
    Shortcut { enabled: view.visible && view.run > 0; sequence: "["; context: Qt.ApplicationShortcut; onActivated: view.show(view.run - 1) }
    Shortcut {
        enabled: view.visible && view.op !== null && view.run < view.op.history.length - 1
        sequence: "]"
        context: Qt.ApplicationShortcut
        onActivated: view.show(view.run + 1)
    }
    Shortcut { enabled: view.visible; sequences: ["PgDown", "Space"]; context: Qt.ApplicationShortcut; onActivated: view.list.contentY = Math.min(view.list.contentY + view.list.height * 0.9, Math.max(0, view.list.contentHeight - view.list.height)) }
    Shortcut { enabled: view.visible; sequence: "PgUp"; context: Qt.ApplicationShortcut; onActivated: view.list.contentY = Math.max(0, view.list.contentY - view.list.height * 0.9) }
    Shortcut { enabled: view.visible && view.gateOutput === ""; sequence: "S"; context: Qt.ApplicationShortcut; onActivated: view.toggleSides() }
}
