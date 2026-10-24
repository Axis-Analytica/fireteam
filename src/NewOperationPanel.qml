import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// The briefing screen for a new operation, and for amending one that isn't
// deployed.
Item {
    id: panel
    visible: false
    signal planned(bool deployNow)
    signal amended(int row, bool deployNow)

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius

    property string error: ""
    property int cycles: 3
    property string roe: "supervised"
    // The row being amended, or -1 for a new operation.
    property int editing: -1
    property int minimumCycles: 1
    // Deploy into a worktree of its own (needs a repository with a commit).
    property bool useWorktree: true
    // The operation being amended already has a worktree, which stays.
    property bool worktreeLocked: false
    // {git, commits, branch} for the directory typed, and the operations
    // already working in place there.
    property var repo: ({})
    property var sharing: []
    readonly property bool worktreeAvailable: repo.commits === true
    property bool savingLoadout: false

    function refreshRepo() {
        repo = directory.text.trim().length > 0 ? ops.repository(directory.text) : ({})
        sharing = directory.text.trim().length > 0 ? ops.sharing(directory.text, editing) : []
    }
    function applyLoadout(loadout) {
        model.currentIndex = Math.max(0, model.find(loadout.model || ""))
        roe = ["free", "supervised", "restricted"].indexOf(loadout.roe) >= 0 ? loadout.roe : "supervised"
        cycles = Math.max(minimumCycles, Math.min(20, loadout.cycles || 3))
        const at = handoff.limits.indexOf(loadout.handoffAt)
        handoff.currentIndex = at >= 0 ? at : 1
        if (!worktreeLocked)
            useWorktree = loadout.worktree === true
        standingField.text = loadout.standing || ""
        overwatchBox.currentIndex = Math.max(0, overwatchBox.keys.indexOf(loadout.overwatch || "off"))
    }
    function currentLoadout(name) {
        return { name: name, model: model.currentIndex === 0 ? "" : model.currentText, roe: roe, cycles: cycles,
                 handoffAt: handoff.limits[handoff.currentIndex], worktree: useWorktree, standing: standingField.text,
                 overwatch: overwatchBox.keys[overwatchBox.currentIndex] }
    }
    Timer { id: repoCheck; interval: 300; onTriggered: panel.refreshRepo() }

    function open() {
        editing = -1
        minimumCycles = 1
        codename.text = ops.suggestCodename()
        objective.text = ""
        error = ""
        cycles = 3
        roe = "supervised"
        model.currentIndex = 0
        handoff.currentIndex = 1
        useWorktree = true
        worktreeLocked = false
        savingLoadout = false
        standingField.text = ""
        overwatchBox.currentIndex = 0
        refreshRepo()
        visible = true
        enter.restart()
        if (directory.text.length === 0)
            directory.forceActiveFocus()
        else
            objective.forceActiveFocus()
    }
    function edit(op, row) {
        editing = row
        // Cycles already run can't be taken back; a finished op gets one more.
        minimumCycles = Math.max(1, op.cyclesDone)
        codename.text = op.codename
        directory.text = op.directory
        objective.text = op.objective
        error = ""
        cycles = Math.max(op.cycles, op.cyclesDone >= op.cycles ? op.cyclesDone + 1 : op.cycles)
        roe = op.roe
        model.currentIndex = Math.max(0, model.find(op.model))
        const at = handoff.limits.indexOf(op.handoffAt)
        handoff.currentIndex = at >= 0 ? at : 1
        useWorktree = op.worktree
        worktreeLocked = op.branch.length > 0
        savingLoadout = false
        standingField.text = op.standing
        overwatchBox.currentIndex = Math.max(0, overwatchBox.keys.indexOf(op.overwatch))
        refreshRepo()
        visible = true
        enter.restart()
        objective.forceActiveFocus()
    }
    function close() { visible = false }
    function submit(deployNow) {
        if (editing >= 0) {
            if (objective.text.trim().length === 0) {
                error = qsTr("Give the fireteam an objective.")
                return
            }
            ops.update(editing, codename.text, objective.text, cycles, roe,
                       model.currentIndex === 0 ? "" : model.currentText, handoff.limits[handoff.currentIndex],
                       useWorktree && worktreeAvailable, standingField.text, overwatchBox.keys[overwatchBox.currentIndex])
            visible = false
            amended(editing, deployNow)
            return
        }
        error = ops.validate(directory.text, objective.text)
        if (error.length > 0)
            return
        ops.create(codename.text, directory.text, objective.text, cycles, roe,
                   model.currentIndex === 0 ? "" : model.currentText, handoff.limits[handoff.currentIndex],
                   useWorktree && worktreeAvailable, standingField.text, overwatchBox.keys[overwatchBox.currentIndex])
        visible = false
        planned(deployNow)
    }

    Connections {
        target: folderPicker
        function onPicked(path) { directory.text = path; objective.forceActiveFocus() }
        function onFailed(message) { panel.error = message }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.78)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: panel.close() }
    }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(760, parent.width - 48)
        height: Math.min(content.implicitHeight + 64, parent.height - 48)
        color: Qt.rgba(0.04, 0.05, 0.065, 0.97)
        border.color: Style.line
        radius: theme.radius
        // Clicks on the panel itself mustn't reach the dismissing backdrop.
        MouseArea { anchors.fill: parent }

        Rectangle { width: parent.width; height: 3; color: theme.accent }

        ParallelAnimation {
            id: enter
            NumberAnimation { target: sheet; property: "opacity"; from: 0; to: 1; duration: 180 }
            NumberAnimation { target: sheet; property: "scale"; from: 0.97; to: 1; duration: 220; easing.type: Easing.OutCubic }
        }

        ScrollView {
            anchors.fill: parent
            anchors.margins: 32
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                id: content
                width: parent.width
                spacing: 18

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: qsTr("Briefing")
                        color: theme.accent
                        font.family: Style.mono
                        font.pixelSize: 11
                        font.letterSpacing: 4 * Style.tracking
                        font.capitalization: Font.AllUppercase
                    }
                    Text {
                        text: panel.editing >= 0 ? qsTr("Amend briefing") : qsTr("Plan operation")
                        color: Style.text
                        font.family: Style.display
                        font.pixelSize: 34
                        font.weight: Font.Black
                        font.letterSpacing: 5 * Style.tracking
                        font.capitalization: Font.AllUppercase
                    }
                }

                // Loadouts: saved sets of model, rules, cycles, and orders.
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        height: 28
                        verticalAlignment: Text.AlignVCenter
                        rightPadding: 4
                        text: qsTr("Loadout")
                        color: Style.dim
                        font.family: Style.display
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.letterSpacing: 3 * Style.tracking
                        font.capitalization: Font.AllUppercase
                    }
                    Repeater {
                        model: ops.loadouts
                        delegate: Rectangle {
                            id: loadoutChip
                            required property var modelData
                            width: loadoutRow.implicitWidth + 20
                            height: 28
                            color: loadoutHover.hovered ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.14) : "transparent"
                            border.color: loadoutHover.hovered ? theme.accent : Style.line
                            radius: Math.min(4, theme.radius)
                            Row {
                                id: loadoutRow
                                anchors.centerIn: parent
                                spacing: 8
                                Text {
                                    text: loadoutChip.modelData.name
                                    color: Style.text
                                    font.family: Style.display
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    font.letterSpacing: 2 * Style.tracking
                                    font.capitalization: Font.AllUppercase
                                }
                                Text {
                                    text: (loadoutChip.modelData.model || qsTr("default")) + " · " + loadoutChip.modelData.cycles
                                    color: Style.faint
                                    font.family: Style.mono
                                    font.pixelSize: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    visible: loadoutHover.hovered
                                    text: "✕"
                                    color: removeHover.hovered ? Style.danger : Style.dim
                                    font.pixelSize: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    HoverHandler { id: removeHover }
                                    TapHandler { onTapped: ops.removeLoadout(loadoutChip.modelData.name) }
                                }
                            }
                            HoverHandler { id: loadoutHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: panel.applyLoadout(loadoutChip.modelData) }
                        }
                    }
                    Text {
                        height: 28
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 4
                        visible: !panel.savingLoadout
                        text: qsTr("+ Save current")
                        color: saveHover.hovered ? theme.accent : Style.dim
                        font.family: Style.display
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        font.letterSpacing: 2 * Style.tracking
                        font.capitalization: Font.AllUppercase
                        HoverHandler { id: saveHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { panel.savingLoadout = true; loadoutName.forceActiveFocus() } }
                    }
                    TextField {
                        id: loadoutName
                        visible: panel.savingLoadout
                        width: 180
                        height: 34
                        topPadding: 4
                        bottomPadding: 4
                        placeholderText: qsTr("Loadout name")
                        font.family: Style.display
                        font.pixelSize: 12
                        onAccepted: {
                            if (text.trim().length > 0)
                                ops.saveLoadout(panel.currentLoadout(text))
                            text = ""
                            panel.savingLoadout = false
                        }
                        Keys.onEscapePressed: { text = ""; panel.savingLoadout = false }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    TextField {
                        id: codename
                        Layout.fillWidth: true
                        placeholderText: qsTr("Codename")
                        font.family: Style.display
                        font.weight: Font.Black
                        font.letterSpacing: 3 * Style.tracking
                        font.capitalization: Font.AllUppercase
                    }
                    TacticalButton { text: qsTr("Reroll"); onClicked: codename.text = ops.suggestCodename() }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    TextField {
                        id: directory
                        Layout.fillWidth: true
                        // Claude Code keeps a session with its project, so an
                        // operation stays where it started.
                        enabled: panel.editing < 0
                        placeholderText: qsTr("Project directory")
                        font.family: Style.mono
                        onTextChanged: repoCheck.restart()
                    }
                    TacticalButton {
                        visible: panel.editing < 0
                        text: folderPicker.busy ? qsTr("Waiting…") : qsTr("Browse")
                        enabled: !folderPicker.busy
                        onClicked: folderPicker.pick(qsTr("Choose the project directory"))
                    }
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 150
                    TextArea {
                        id: objective
                        placeholderText: qsTr("Objective: what should the fireteam build or fix?")
                        wrapMode: TextArea.Wrap
                        font.family: Style.display
                        font.pixelSize: 14
                    }
                }

                SectionLabel { Layout.fillWidth: true; text: qsTr("Cycles") }
                RowLayout {
                    spacing: 14
                    TacticalButton { text: "−"; enabled: panel.cycles > panel.minimumCycles; onClicked: panel.cycles-- }
                    Text {
                        Layout.preferredWidth: 64
                        horizontalAlignment: Text.AlignHCenter
                        text: Style.pad(panel.cycles)
                        color: Style.text
                        font.family: Style.display
                        font.pixelSize: 34
                        font.weight: Font.Black
                    }
                    TacticalButton { text: "+"; enabled: panel.cycles < 20; onClicked: panel.cycles++ }
                    Text {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        text: qsTr("Each cycle is one Claude Code run that picks up where the last left off and files an HTML debrief.")
                        wrapMode: Text.Wrap
                        color: Style.dim
                        font.family: Style.display
                        font.pixelSize: 12
                    }
                }

                SectionLabel { Layout.fillWidth: true; text: qsTr("Rules of engagement") }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Repeater {
                        model: [
                            { key: "restricted", title: qsTr("Restricted"),
                              body: qsTr("Edits files freely. Other commands follow your Claude Code permission settings; anything not pre-approved is refused.") },
                            { key: "supervised", title: qsTr("Supervised"),
                              body: qsTr("Edits files freely. Any other command not already allowed comes to you live, mid-cycle, while the agent waits.") },
                            { key: "free", title: qsTr("Weapons free"),
                              body: qsTr("Full autonomy: runs any command without asking. Only for projects you can afford to have changed.") }
                        ]
                        delegate: Rectangle {
                            id: card
                            required property var modelData
                            readonly property bool chosen: panel.roe === modelData.key
                            readonly property color tone: modelData.key === "free" ? Style.danger : theme.accent
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: 1
                            implicitHeight: cardText.implicitHeight + 28
                            radius: theme.radius
                            color: chosen ? Qt.rgba(tone.r, tone.g, tone.b, 0.12) : "transparent"
                            border.color: chosen ? tone : Style.line
                            border.width: chosen ? 2 : 1
                            ColumnLayout {
                                id: cardText
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 14
                                spacing: 4
                                Text {
                                    text: card.modelData.title
                                    color: card.chosen ? card.tone : Style.text
                                    font.family: Style.display
                                    font.pixelSize: 15
                                    font.weight: Font.Black
                                    font.letterSpacing: 3 * Style.tracking
                                    font.capitalization: Font.AllUppercase
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: card.modelData.body
                                    wrapMode: Text.Wrap
                                    color: Style.dim
                                    font.family: Style.display
                                    font.pixelSize: 12
                                }
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: panel.roe = card.modelData.key }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Text {
                        text: qsTr("Model")
                        color: Style.dim
                        font.family: Style.display
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.letterSpacing: 3 * Style.tracking
                        font.capitalization: Font.AllUppercase
                    }
                    ComboBox {
                        id: model
                        Layout.preferredWidth: 200
                        model: [qsTr("Account default"), "opus", "sonnet", "haiku"]
                    }
                    Item { Layout.preferredWidth: 12 }
                    Text {
                        text: qsTr("Hand off at")
                        color: Style.dim
                        font.family: Style.display
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.letterSpacing: 3 * Style.tracking
                        font.capitalization: Font.AllUppercase
                    }
                    ComboBox {
                        id: handoff
                        Layout.preferredWidth: 150
                        // Context sizes at which the next cycle moves to a fresh session.
                        readonly property var limits: [150000, 250000, 400000, 600000, 0]
                        model: ["150k", "250k", "400k", "600k", qsTr("Never")]
                        currentIndex: 1
                    }
                    Item { Layout.fillWidth: true }
                }

                SectionLabel { Layout.fillWidth: true; text: qsTr("Deployment") }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Switch {
                        id: worktreeSwitch
                        checked: panel.useWorktree && panel.worktreeAvailable
                        enabled: panel.worktreeAvailable && !panel.worktreeLocked
                        onToggled: panel.useWorktree = checked
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: qsTr("Own worktree")
                            color: worktreeSwitch.enabled ? Style.text : Style.dim
                            font.family: Style.display
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            font.letterSpacing: 2 * Style.tracking
                            font.capitalization: Font.AllUppercase
                        }
                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            color: Style.dim
                            font.family: Style.display
                            font.pixelSize: 12
                            text: panel.worktreeLocked ? qsTr("Working on its own branch; extract or discard it to change this.")
                                : panel.repo.git !== true ? qsTr("Not a git repository, so the agent works in place.")
                                : panel.repo.commits !== true ? qsTr("The repository has no commits yet; a worktree needs one. Until then the agent works in place.")
                                : panel.useWorktree ? qsTr("The agent works on its own branch from %1's last commit, so other operations can share the repository. Uncommitted changes aren't included. Extract merges it back.").arg(panel.repo.branch || "HEAD")
                                : qsTr("The agent works directly in the project directory.")
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: !(panel.useWorktree && panel.worktreeAvailable) && panel.sharing.length > 0
                    text: qsTr("⚠ %1 also works in place here. They'll take turns rather than run at once; give one its own worktree to run both together.").arg(panel.sharing.join(", "))
                    wrapMode: Text.Wrap
                    color: Style.amber
                    font.family: Style.display
                    font.pixelSize: 12
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Text {
                        text: qsTr("Overwatch")
                        color: Style.dim
                        font.family: Style.display
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.letterSpacing: 3 * Style.tracking
                        font.capitalization: Font.AllUppercase
                    }
                    ComboBox {
                        id: overwatchBox
                        Layout.preferredWidth: 200
                        readonly property var keys: ["off", "review", "fix"]
                        model: [qsTr("Off"), qsTr("Review"), qsTr("Review and fix")]
                    }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: Style.dim
                        font.family: Style.display
                        font.pixelSize: 12
                        text: overwatchBox.currentIndex === 0 ? qsTr("No review; the operation completes after its last cycle.")
                            : overwatchBox.currentIndex === 1 ? qsTr("After the last cycle, a separate read-only session grades the work against the objective.")
                            : qsTr("As Review, and if it falls short, one more cycle fixes the findings before a second review.")
                    }
                }
                TextField {
                    id: standingField
                    Layout.fillWidth: true
                    placeholderText: qsTr("Standing orders for every cycle (optional), e.g. Run the tests before finishing.")
                    font.family: Style.display
                    font.pixelSize: 13
                }

                Text {
                    Layout.fillWidth: true
                    visible: panel.error.length > 0
                    text: "⚠ " + panel.error
                    wrapMode: Text.Wrap
                    color: Style.danger
                    font.family: Style.display
                    font.pixelSize: 13
                    font.weight: Font.Bold
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    spacing: 10
                    TacticalButton { text: qsTr("Cancel"); key: "Esc"; onClicked: panel.close() }
                    Item { Layout.fillWidth: true }
                    TacticalButton {
                        text: panel.editing >= 0 ? qsTr("Save") : qsTr("Hold at standby")
                        onClicked: panel.submit(false)
                    }
                    TacticalButton {
                        text: panel.editing >= 0 ? qsTr("Save and deploy") : qsTr("Deploy")
                        key: "Ctrl+Enter"
                        primary: true
                        onClicked: panel.submit(true)
                    }
                }
            }
        }
    }

    Shortcut {
        enabled: panel.visible
        sequences: ["Ctrl+Return", "Ctrl+Enter"]
        context: Qt.ApplicationShortcut
        onActivated: panel.submit(true)
    }
}
