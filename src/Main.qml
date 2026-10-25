import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 1360
    height: 860
    minimumWidth: 560
    minimumHeight: 520
    visible: true
    title: "Fireteam"
    color: Style.bg

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius
    Material.background: Style.panel
    font.family: Style.body

    FontLoader { source: "qrc:/fonts/MartianMono.ttf" }
    // Red Hat ships as static weights: Qt matches font.weight to them exactly,
    // which it doesn't do for a variable font's weight axis.
    FontLoader { source: "qrc:/fonts/RedHatText-Regular.ttf" }
    FontLoader { source: "qrc:/fonts/RedHatText-Medium.ttf" }
    FontLoader { source: "qrc:/fonts/RedHatText-SemiBold.ttf" }
    FontLoader { source: "qrc:/fonts/RedHatDisplay-Medium.ttf" }
    FontLoader { source: "qrc:/fonts/RedHatDisplay-SemiBold.ttf" }

    // Hyprland tiles windows, so the board has to read in a narrow column too.
    readonly property bool narrow: width < 1100
    readonly property bool overlayOpen: briefing.visible || help.visible || confirm.visible || radio.visible || intel.visible
                                        || insertion.visible || authorisation.visible || serviceRecord.visible
                                        || waitingPanel.visible || campaignBoard.visible || terminalPanel.visible
                                        || manualPanel.visible || replayView.visible || searchPanel.visible
                                        || optionsPanel.visible || graphPanel.visible
    // The theatre map in place of the roster and detail.
    property bool mapView: false
    readonly property var selected: roster.currentItem

    // Archived operations are only on the board when asked for.
    property bool showArchived: false
    function move(step) {
        let next = roster.currentIndex
        for (let i = 0; i < roster.count; ++i) {
            next = Math.max(0, Math.min(roster.count - 1, next + step))
            const item = roster.itemAtIndex(next)
            if (!item || !item.hidden) {
                roster.currentIndex = next
                return
            }
        }
    }
    function deploySelected() { if (selected) ops.deploy(roster.currentIndex) }
    function ordersSelected() { if (selected) radio.open(selected, roster.currentIndex) }
    function editSelected() { if (selected && selected.status !== "deployed") briefing.edit(selected, roster.currentIndex) }
    function diffSelected(run) {
        if (selected && selected.history.length > 0)
            intel.open(selected, roster.currentIndex, run === undefined ? selected.history.length - 1 : run)
    }
    function rollback(run) {
        const entry = selected.history[run]
        const row = roster.currentIndex
        confirm.ask(qsTr("Roll back to before cycle %1?").arg(entry.cycle),
                    qsTr("Every file in the repository goes back to how it was when cycle %1 started, including changes made since by you. The current state is snapshotted first, so Undo rollback puts it all back.").arg(entry.cycle),
                    qsTr("Roll back"), () => ops.rollback(row, run))
    }
    // A: what the agent is waiting on right now, or else refused commands and
    // standing approvals.
    function authoriseSelected() {
        if (!selected)
            return
        if (selected.questions.length + selected.prompts.length > 0)
            waitingPanel.open(selected, roster.currentIndex)
        else
            authorisation.open(selected, roster.currentIndex)
    }
    function holdSelected() { if (selected && selected.status === "deployed") ops.setHold(roster.currentIndex, !selected.hold) }
    function abortSelected() {
        if (selected && (selected.status === "staged" || selected.status === "pinned")) {
            ops.abort(roster.currentIndex)
            return
        }
        if (!selected || selected.status !== "deployed")
            return
        const row = roster.currentIndex
        confirm.ask(qsTr("Abort %1?").arg(selected.codename),
                    qsTr("The agent is stopped mid-cycle. Files it already changed stay changed."),
                    qsTr("Abort"), () => ops.abort(row))
    }
    function removeSelected() {
        if (!selected || selected.status === "deployed")
            return
        const row = roster.currentIndex
        confirm.ask(qsTr("Stand down %1?").arg(selected.codename),
                    selected.branch.length > 0
                    ? qsTr("The operation, its comms and its debriefs are deleted from Fireteam. Its worktree's work is committed to branch %1, which stays in your repository.").arg(selected.branch)
                    : qsTr("The operation, its comms and its debriefs are deleted from Fireteam. The project itself isn't touched."),
                    qsTr("Stand down"), () => ops.remove(row))
    }
    function extractSelected() {
        if (!selected || selected.branch.length === 0)
            return
        const row = roster.currentIndex
        const summary = ops.worktreeSummary(row)
        confirm.ask(qsTr("Extract %1?").arg(selected.codename),
                    qsTr("Commits the worktree and merges %1 (%2 files, +%3 −%4) into %5 in your repository. If it conflicts with your branch, nothing is changed and the conflicts are listed.")
                        .arg(summary.branch).arg(summary.files).arg(summary.added).arg(summary.removed)
                        .arg(summary.target || qsTr("the checked-out commit")),
                    qsTr("Extract"), () => ops.extract(row))
    }
    function discardSelected() {
        if (!selected || selected.branch.length === 0)
            return
        const row = roster.currentIndex
        confirm.ask(qsTr("Discard %1's work?").arg(selected.codename),
                    qsTr("The worktree and branch %1 are deleted, with everything the agent did there. Your own branch isn't touched.").arg(selected.branch),
                    qsTr("Discard"), () => ops.discard(row))
    }
    function quit() {
        if (ops.deployedCount > 0)
            confirm.ask(qsTr("Pull out?"),
                        qsTr("%n agent(s) still deployed. Quitting stops them mid-cycle; you can resume later.", "", ops.deployedCount),
                        qsTr("Quit"), () => Qt.quit())
        else
            Qt.quit()
    }

    // Where on screen an operation's event happened: its roster entry, or its
    // marker on the map.
    function eventPoint(row) {
        const item = roster.itemAtIndex(row)
        if (!win.mapView && item)
            return item.mapToItem(backdrop, item.width * 0.4, item.height / 2)
        return Qt.point(backdrop.width / 2, backdrop.height / 2)
    }

    // Tell someone who's looking elsewhere; the board already shows it.
    Connections {
        target: ops
        function onAlert(opId, title, body) {
            if (!win.active)
                notifier.send(opId, title, body)
        }
        function onWaiting(row) {
            Sfx.play("radio")
        }
        function onDeployed(row) {
            const op = roster.itemAtIndex(row)
            if (!op || !win.active || !Prefs.insertion)
                return
            const lines = [qsTr("Fireteam %1, you are cleared hot."), qsTr("%1, green light. Move out."),
                           qsTr("%1, you're go for insertion."), qsTr("All stations, %1 is on the move.")]
            insertion.play(op.codename, lines[Math.floor(Math.random() * lines.length)].arg(op.codename),
                           qsTr("Cycle %1 of %2 · %3 · %4").arg(op.cyclesDone + 1)
                               .arg(Math.max(op.cycles, op.cyclesDone + 1))
                               .arg(op.model || qsTr("default model"))
                               .arg(op.roe === "free" ? qsTr("weapons free") : qsTr("restricted")))
        }
        function onCycleFinished(row, cycle) {
            const p = win.eventPoint(row)
            backdrop.burst("spark", p.x, p.y)
            Sfx.play("done")
        }
        function onOperationFinished(row) {
            const op = roster.itemAtIndex(row)
            const p = win.eventPoint(row)
            if (!op)
                return
            if (op.status === "complete") {
                backdrop.burst("victory", p.x, p.y)
                Sfx.play("complete")
            } else if (op.status === "failed" || op.status === "aborted") {
                backdrop.burst("flare", p.x, p.y)
                Sfx.play("fail")
            }
        }
    }
    Connections {
        target: notifier
        function onActivated(opId) {
            const row = ops.rowOfId(opId)
            if (row >= 0)
                roster.currentIndex = row
            win.raise()
            win.requestActivate()
        }
    }

    onClosing: (close) => {
        if (ops.deployedCount > 0 && !confirm.visible) {
            close.accepted = false
            quit()
        }
    }

    Shortcut { sequences: ["?", "Shift+?"]; context: Qt.ApplicationShortcut; enabled: !briefing.visible && !confirm.visible; onActivated: help.visible = !help.visible }
    Shortcut { sequence: "Q"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: win.quit() }
    Shortcut { sequence: "N"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: briefing.open() }
    Shortcut { sequence: "Space"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: win.deploySelected() }
    Shortcut { sequence: "M"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: { win.mapView = !win.mapView; Sfx.play("open") } }
    Shortcut { sequence: "Shift+M"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: Sfx.toggle() }
    Shortcut { sequence: "F"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: manualPanel.open(win.selected ? win.selected.directory : "") }
    Shortcut { sequence: "Shift+R"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen && win.selected !== null; onActivated: replayView.open(win.selected, roster.currentIndex) }
    Shortcut { sequences: [StandardKey.Find]; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: searchPanel.open() }
    Shortcut { sequence: "P"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: terminalPanel.open() }
    Shortcut { sequences: [",", StandardKey.Preferences]; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: optionsPanel.open("options") }
    Shortcut { sequence: "G"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: graphPanel.open(win.selected ? win.selected.directory : "", "") }
    Shortcut { sequence: "C"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: campaignBoard.open() }
    Shortcut { sequence: "S"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: serviceRecord.open() }
    Shortcut { sequence: "A"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: win.authoriseSelected() }
    Shortcut { sequence: "T"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: win.ordersSelected() }
    Shortcut { sequence: "H"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: win.holdSelected() }
    Shortcut { sequence: "E"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: win.editSelected() }
    Shortcut { sequence: "V"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: win.diffSelected() }
    Shortcut { sequence: "/"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen && win.selected !== null; onActivated: detailPanel.focusSearch() }
    Shortcut { sequence: "X"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: win.abortSelected() }
    Shortcut { sequence: "R"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: ops.openLatestReport(roster.currentIndex) }
    Shortcut { sequence: "D"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: ops.openDossier(roster.currentIndex) }
    Shortcut { sequence: "O"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: ops.openProject(roster.currentIndex) }
    Shortcut { sequence: "Delete"; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: win.removeSelected() }
    Shortcut { sequences: ["Down", "J"]; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: win.move(1) }
    Shortcut { sequences: ["Up", "K"]; context: Qt.ApplicationShortcut; enabled: !win.overlayOpen; onActivated: win.move(-1) }
    Shortcut {
        sequence: "Esc"
        context: Qt.ApplicationShortcut
        enabled: win.overlayOpen
        onActivated: {
            if (insertion.visible) insertion.skip()
            else if (confirm.visible) confirm.visible = false
            else if (help.visible) help.visible = false
            else if (intel.visible) intel.close()
            else if (authorisation.visible) authorisation.close()
            else if (waitingPanel.visible) waitingPanel.close()
            else if (campaignBoard.visible) campaignBoard.close()
            else if (terminalPanel.visible) terminalPanel.close()
            else if (manualPanel.visible) manualPanel.close()
            else if (replayView.visible) replayView.close()
            else if (searchPanel.visible) searchPanel.close()
            else if (optionsPanel.visible) optionsPanel.close()
            else if (graphPanel.visible) graphPanel.close()
            else if (serviceRecord.visible) serviceRecord.close()
            else if (radio.visible) radio.close()
            else briefing.close()
        }
    }

    // Takes keyboard focus back from a closed panel's text fields, which would
    // otherwise swallow the single-key shortcuts.
    Item { id: board; focus: true }

    TacticalBackdrop {
        id: backdrop
        anchors.fill: parent
        accent: theme.accent
        heat: ops.deployedCount
        active: win.visibility !== Window.Minimized && Prefs.motion
    }

    // Right-to-left languages mirror the window; the Translator sets the
    // application's layout direction.
    Item {
        anchors.fill: parent
        LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
        LayoutMirroring.childrenInherit: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: win.narrow ? 18 : 32
            anchors.bottomMargin: 20
            spacing: 18

            // Header: the wordmark on the left; the link, usage, squad and clock
            // on the right, printed as a tool prints its figures.
            RowLayout {
                Layout.fillWidth: true
                spacing: 22
                ColumnLayout {
                    spacing: 6
                    RowLayout {
                        spacing: 12
                        Rectangle { implicitWidth: 10; implicitHeight: 10; color: theme.accent; Layout.alignment: Qt.AlignVCenter }
                        Text {
                            id: brand
                            text: "FIRETEAM"
                            color: Style.text
                            font.family: Style.mono
                            font.variableAxes: Style.wide
                            font.pixelSize: 30
                            font.weight: Font.Medium
                            font.letterSpacing: -0.6
                        }
                    }
                    Text {
                        Layout.leftMargin: 22
                        text: qsTr("Base camp  //  operations board")
                        color: Style.dim
                        font.family: Style.body
                        font.pixelSize: 13
                    }
                }
                Item { Layout.fillWidth: true }

                ColumnLayout {
                    visible: win.width > 820
                    spacing: 2
                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: 8
                        Rectangle {
                            implicitWidth: 6; implicitHeight: 6
                            color: ops.linkStatus === "online" ? Style.good : ops.linkStatus === "checking" ? Style.amber : Style.danger
                        }
                        Text {
                            text: ops.linkStatus === "online" ? qsTr("Online · %1").arg(ops.account)
                                : ops.linkStatus === "checking" ? qsTr("Checking…")
                                : ops.linkStatus === "missing" ? qsTr("claude not installed")
                                : qsTr("Not logged in: run claude to sign in")
                            color: ops.linkStatus === "online" ? Style.text2 : Style.danger
                            font.family: Style.mono
                            font.variableAxes: Style.narrow
                            font.pixelSize: 12
                        }
                    }
                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: "# " + qsTr("Claude link").toLowerCase()
                        color: Style.dim
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                        font.pixelSize: 10
                    }
                }
                Rectangle { visible: win.width > 820; implicitWidth: 1; implicitHeight: 40; color: Style.line }
                // The field terminal, while it's on.
                ColumnLayout {
                    visible: terminal.enabled && win.width > 900
                    spacing: 2
                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: terminal.listening ? qsTr("◉ %n on link", "", terminal.clients) : qsTr("Not listening")
                        color: terminal.listening ? (terminal.clients > 0 ? Style.good : Style.text2) : Style.danger
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                        font.pixelSize: 12
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: terminalPanel.open() }
                    }
                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: "# " + qsTr("Terminal").toLowerCase()
                        color: Style.dim
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                        font.pixelSize: 10
                    }
                }
                Rectangle { visible: terminal.enabled && win.width > 900; implicitWidth: 1; implicitHeight: 40; color: Style.line }
                // The plan's usage, from the latest run's report.
                ColumnLayout {
                    visible: win.width > 980 && ops.usage.windows !== undefined
                    spacing: 4
                    Repeater {
                        model: [["five_hour", qsTr("5H")], ["seven_day", qsTr("7D")]]
                        delegate: RowLayout {
                            id: usageRow
                            required property var modelData
                            readonly property var window: ops.usage.windows ? ops.usage.windows[modelData[0]] : undefined
                            readonly property real used: window ? window.utilization : 0
                            visible: window !== undefined
                            Layout.alignment: Qt.AlignRight
                            spacing: 8
                            Text {
                                text: usageRow.modelData[1]
                                color: Style.dim
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 10
                            }
                            // Ten cells, lit as the window fills.
                            Row {
                                spacing: 2
                                Repeater {
                                    model: 10
                                    Rectangle {
                                        required property int index
                                        width: 5; height: 8
                                        color: index < Math.round(usageRow.used * 10)
                                               ? (usageRow.used >= 0.9 ? Style.danger : usageRow.used >= 0.7 ? Style.amber : theme.accent)
                                               : Style.line
                                    }
                                }
                            }
                            Text {
                                Layout.preferredWidth: 34
                                horizontalAlignment: Text.AlignRight
                                text: Math.round(usageRow.used * 100) + "%"
                                color: Style.text2
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 10
                            }
                        }
                    }
                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: "# " + (ops.usage.status === "rejected" ? qsTr("Plan · limit reached") : qsTr("Plan usage")).toLowerCase()
                        color: ops.usage.status === "rejected" ? Style.danger : Style.dim
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                        font.pixelSize: 10
                    }
                }
                Rectangle { visible: win.width > 980 && ops.usage.windows !== undefined; implicitWidth: 1; implicitHeight: 40; color: Style.line }
                // Deployed against the squad's limit, with the queue behind it.
                ColumnLayout {
                    spacing: 2
                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: 10
                        Text {
                            text: "−"
                            color: squadLess.hovered ? theme.accent : Style.faint
                            font.family: Style.mono
                            font.pixelSize: 14
                            HoverHandler { id: squadLess; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: ops.maxDeployed = ops.maxDeployed === 0 ? 6 : Math.max(1, ops.maxDeployed - 1) }
                        }
                        Text {
                            text: Style.pad(ops.deployedCount) + "/" + (ops.maxDeployed === 0 ? "∞" : Style.pad(ops.maxDeployed))
                            color: ops.deployedCount > 0 ? theme.accent : Style.text
                            font.family: Style.mono
                            font.variableAxes: Style.figure
                            font.pixelSize: 24
                        }
                        Text {
                            text: "+"
                            color: squadMore.hovered ? theme.accent : Style.faint
                            font.family: Style.mono
                            font.pixelSize: 14
                            HoverHandler { id: squadMore; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: ops.maxDeployed = ops.maxDeployed === 0 || ops.maxDeployed >= 6 ? 0 : ops.maxDeployed + 1 }
                        }
                    }
                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: "# " + qsTr("Squad").toLowerCase() + (ops.stagedCount > 0 ? " · " + qsTr("+%1 staged").arg(ops.stagedCount) : "")
                        color: ops.stagedCount > 0 ? Style.amber : Style.dim
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                        font.pixelSize: 10
                    }
                }
                Rectangle { visible: !win.narrow; implicitWidth: 1; implicitHeight: 40; color: Style.line }
                Figure {
                    id: clock
                    visible: !win.narrow
                    value: Qt.formatTime(new Date(), "HH:mm:ss")
                    comment: Qt.formatDate(new Date(), "ddd d MMM").toLowerCase()
                    Timer { interval: 1000; running: true; repeat: true; onTriggered: { clock.value = Qt.formatTime(new Date(), "HH:mm:ss"); clock.comment = Qt.formatDate(new Date(), "ddd d MMM").toLowerCase() } }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

            // The board stays alive under the map, so the selection does too.
            RowLayout {
                anchors.fill: parent
                spacing: win.narrow ? 16 : 32
                opacity: win.mapView ? 0 : 1
                enabled: !win.mapView
                Behavior on opacity { NumberAnimation { duration: 220 } }

                // The roster of operations, as a game menu.
                ColumnLayout {
                    Layout.preferredWidth: win.narrow ? 260 : 380
                    Layout.maximumWidth: win.narrow ? 260 : 380
                    Layout.fillWidth: false
                    Layout.fillHeight: true
                    spacing: 10
                    SectionLabel { Layout.fillWidth: true; text: qsTr("Operations"); detail: Style.pad(roster.count) }
                    ListView {
                        id: roster
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: ops
                        currentIndex: count > 0 ? 0 : -1
                        onCurrentIndexChanged: Sfx.play("select")
                        highlightFollowsCurrentItem: false
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: RosterEntry { onActivated: roster.currentIndex = index }
                        add: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 300 }
                                NumberAnimation { property: "x"; from: -60; to: 0; duration: 340; easing.type: Easing.OutCubic }
                            }
                        }
                        displaced: Transition { NumberAnimation { properties: "y"; duration: 220; easing.type: Easing.OutCubic } }
                        ScrollBar.vertical: ScrollBar {}
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: ops.archivedCount > 0
                        text: win.showArchived ? qsTr("Hide the archive") : qsTr("Show the archive (%1)").arg(ops.archivedCount)
                        horizontalAlignment: Text.AlignHCenter
                        color: archiveHover.hovered ? theme.accent : Style.dim
                        font.family: Style.body
                        font.pixelSize: 12
                        HoverHandler { id: archiveHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: win.showArchived = !win.showArchived }
                    }
                    TacticalButton {
                        Layout.fillWidth: true
                        text: qsTr("Plan operation")
                        key: "N"
                        primary: roster.count === 0
                        onClicked: briefing.open()
                    }
                }

                Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Style.line }

                OperationDetail {
                    id: detailPanel
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    op: win.selected
                    row: roster.currentIndex
                    onDeployRequested: win.deploySelected()
                    onAbortRequested: win.abortSelected()
                    onRemoveRequested: win.removeSelected()
                    onOrdersRequested: win.ordersSelected()
                    onEditRequested: win.editSelected()
                    onDiffRequested: (run) => win.diffSelected(run)
                    onAuthorisationRequested: win.authoriseSelected()
                    onExtractRequested: win.extractSelected()
                    onReplayRequested: replayView.open(win.selected, roster.currentIndex)
                    onGraphRequested: graphPanel.open(win.selected.directory, win.selected.opId)
                    onDiscardRequested: win.discardSelected()
                }
            }

            TacticalMap {
                anchors.fill: parent
                visible: opacity > 0
                opacity: win.mapView ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220 } }
                currentRow: roster.currentIndex
                selected: win.selected
                onPicked: (row) => roster.currentIndex = row
            }
            }

            // Footer: the controls, the way a game menu lists them.
            RowLayout {
                Layout.fillWidth: true
                spacing: 22
                KeyHint { key: "N"; label: qsTr("Plan") }
                KeyHint { key: qsTr("Space"); label: qsTr("Deploy") }
                // The rest show as room allows (a long language or a narrow
                // tile), cut at the edge rather than widening the window; ?
                // lists them all.
                Item {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    implicitHeight: 20
                    clip: true
                    Flow {
                        width: parent.width
                        spacing: 22
                        KeyHint { key: "T"; label: qsTr("Orders") }
                        KeyHint { key: "X"; label: qsTr("Abort") }
                        KeyHint { key: "V"; label: qsTr("Intel") }
                        KeyHint { key: "M"; label: win.mapView ? qsTr("Board") : qsTr("Map") }
                        KeyHint { key: "G"; label: qsTr("Graph") }
                        KeyHint { key: "C"; label: qsTr("Campaigns") }
                        KeyHint { key: "S"; label: qsTr("Record") }
                        KeyHint { key: "R"; label: qsTr("Debrief") }
                    }
                }
                KeyHint { key: ","; label: qsTr("Options") }
                KeyHint { key: "?"; label: qsTr("Controls") }
                KeyHint { key: "Q"; label: qsTr("Quit") }
                Text {
                    visible: win.width > 1560
                    text: "fireteam " + Qt.application.version
                    color: Style.faint
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 11
                }
            }
        }

        NewOperationPanel {
            id: briefing
            anchors.fill: parent
            onVisibleChanged: visible ? Sfx.play("open") : board.forceActiveFocus()
            onPlanned: (deployNow) => {
                roster.currentIndex = 0
                if (deployNow)
                    ops.deploy(0)
            }
            onAmended: (row, deployNow) => {
                if (deployNow)
                    ops.deploy(row)
            }
        }
        RadioPanel {
            id: radio
            anchors.fill: parent
            onVisibleChanged: visible ? Sfx.play("open") : board.forceActiveFocus()
        }
        DiffView {
            id: intel
            anchors.fill: parent
            onVisibleChanged: visible ? Sfx.play("open") : board.forceActiveFocus()
            onRollbackRequested: (run) => win.rollback(run)
        }
        AuthorisationPanel {
            id: authorisation
            anchors.fill: parent
            onVisibleChanged: visible ? Sfx.play("open") : board.forceActiveFocus()
            onResumeRequested: ops.deploy(row)
        }
        FieldManualPanel {
            id: manualPanel
            anchors.fill: parent
            onVisibleChanged: visible ? Sfx.play("open") : board.forceActiveFocus()
        }
        ReplayView {
            id: replayView
            anchors.fill: parent
            onVisibleChanged: visible ? Sfx.play("open") : board.forceActiveFocus()
        }
        SearchPanel {
            id: searchPanel
            anchors.fill: parent
            onVisibleChanged: if (!visible) board.forceActiveFocus()
            onPicked: (row, path) => {
                const item = roster.itemAtIndex(row)
                if (item && item.archived)
                    win.showArchived = true
                roster.currentIndex = row
                searchPanel.close()
                if (path.length > 0)
                    ops.openReport(path)
            }
        }
        TerminalPanel {
            id: terminalPanel
            anchors.fill: parent
            onVisibleChanged: visible ? Sfx.play("open") : board.forceActiveFocus()
        }
        CampaignBoard {
            id: campaignBoard
            anchors.fill: parent
            onVisibleChanged: visible ? Sfx.play("open") : board.forceActiveFocus()
            onOperationPicked: (row) => { roster.currentIndex = row; campaignBoard.close() }
        }
        WaitingPanel {
            id: waitingPanel
            anchors.fill: parent
            onVisibleChanged: visible ? Sfx.play("open") : board.forceActiveFocus()
        }
        ServiceRecord {
            id: serviceRecord
            anchors.fill: parent
            onVisibleChanged: visible ? Sfx.play("open") : board.forceActiveFocus()
        }
        GraphPanel {
            id: graphPanel
            anchors.fill: parent
            onVisibleChanged: visible ? Sfx.play("open") : board.forceActiveFocus()
        }
        OptionsPanel {
            id: optionsPanel
            anchors.fill: parent
            onVisibleChanged: visible ? Sfx.play("open") : board.forceActiveFocus()
            onTerminalRequested: { optionsPanel.close(); terminalPanel.open() }
            onControlsRequested: { optionsPanel.close(); help.visible = true }
        }
        HelpOverlay { id: help; anchors.fill: parent; onVisibleChanged: if (visible) Sfx.play("open") }
        ConfirmPanel { id: confirm; anchors.fill: parent }
        DeploySequence {
            id: insertion
            anchors.fill: parent
            onVisibleChanged: if (!visible) board.forceActiveFocus()
        }
    }

}
