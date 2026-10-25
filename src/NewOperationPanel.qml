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
    Material.background: Style.panel
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

    // Proof: the project's checks (toggled), what "done" means, and what to
    // screenshot.
    property var gates: []
    property bool previewOn: false
    function refreshRepo() {
        repo = directory.text.trim().length > 0 ? ops.repository(directory.text) : ({})
        sharing = directory.text.trim().length > 0 ? ops.sharing(directory.text, editing) : []
        if (editing < 0)
            gates = directory.text.trim().length > 0 ? ops.detectGates(directory.text) : []
    }
    function toggleGate(index) {
        const next = gates.map(g => Object.assign({}, g))
        next[index].enabled = !next[index].enabled
        gates = next
    }
    function addGate(command) {
        if (command.trim().length === 0)
            return
        gates = gates.concat([{ name: command.trim().split(" ").slice(0, 2).join(" "), command: command.trim(), enabled: true }])
    }
    function saveProof(row) {
        ops.setProof(row, gates, criteriaField.text, previewOn ? previewCommand.text : "", previewOn ? previewUrl.text : "")
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
    // A recipe fills the objective and criteria, and brings its loadout.
    function applyRecipe(recipe) {
        objective.text = recipe.objective || ""
        criteriaField.text = recipe.criteria || ""
        const loadout = ops.loadouts.find(l => l.name === recipe.loadout)
        if (loadout)
            applyLoadout(loadout)
    }
    property bool savingRecipe: false
    function currentLoadout(name) {
        return { name: name, model: model.currentIndex === 0 ? "" : model.currentText, roe: roe, cycles: cycles,
                 handoffAt: handoff.limits[handoff.currentIndex], worktree: useWorktree, standing: standingField.text,
                 overwatch: overwatchBox.keys[overwatchBox.currentIndex] }
    }
    Timer { id: repoCheck; interval: 300; onTriggered: panel.refreshRepo() }

    // A new briefing filled from a one-line request (the command palette).
    function prefill(plan) {
        open()
        if (plan.directory) directory.text = plan.directory
        if (plan.codename) codename.text = plan.codename
        objective.text = plan.objective || ""
        refreshRepo()
        objective.forceActiveFocus()
    }
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
        criteriaField.text = ""
        previewOn = false
        previewCommand.text = ""
        previewUrl.text = ""
        overwatchBox.currentIndex = 0
        // The loadout chosen in Options, if it still exists.
        const start = ops.loadouts.find(l => l.name === Prefs.defaultLoadout)
        if (start)
            applyLoadout(start)
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
        gates = op.gates
        criteriaField.text = op.criteria.map(c => c.text).join("\n")
        previewOn = op.preview.url !== undefined && op.preview.url.length > 0
        previewCommand.text = op.preview.command || ""
        previewUrl.text = op.preview.url || ""
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
            saveProof(editing)
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
        saveProof(0)
        visible = false
        planned(deployNow)
    }

    Connections {
        target: folderPicker
        function onPicked(path) { directory.text = path; objective.forceActiveFocus() }
        function onFailed(message) { panel.error = message }
    }


    // Small type roles used across the sheet.
    component FieldLabel: Text {
        color: Style.text2
        font.family: Style.body
        font.pixelSize: 12
        font.weight: Font.Medium
    }
    component Note: Text {
        wrapMode: Text.Wrap
        color: Style.dim
        lineHeight: 1.3
        font.family: Style.body
        font.pixelSize: 12
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Style.bg.r, Style.bg.g, Style.bg.b, 0.86)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: panel.close() }
    }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(800, parent.width - 48)
        height: Math.min(header.height + 1 + content.implicitHeight + 48 + 1 + footer.implicitHeight, parent.height - 48)
        color: Style.panel
        border.color: Style.lineStrong
        radius: theme.radius
        transform: Translate { id: lift }
        // Clicks on the panel itself mustn't reach the dismissing backdrop.
        MouseArea { anchors.fill: parent }
        Brackets { anchors.fill: parent; anchors.margins: -1; size: 12 }

        ParallelAnimation {
            id: enter
            NumberAnimation { target: sheet; property: "opacity"; from: 0; to: 1; duration: 140 }
            NumberAnimation { target: lift; property: "y"; from: 8; to: 0; duration: 180; easing.type: Easing.OutCubic }
        }

        // Header: eyebrow and title.
        Item {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            height: 92
            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 32
                anchors.rightMargin: 32
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 18
                spacing: 4
                Text {
                    text: "# " + qsTr("Briefing").toLowerCase()
                    color: Style.dim
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 11
                }
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: panel.editing >= 0 ? qsTr("Amend briefing") : qsTr("Plan operation")
                    color: Style.text
                    font.family: Style.display
                    font.pixelSize: 30
                    font.weight: Font.DemiBold
                    font.letterSpacing: -0.6
                }
            }
        }
        Rectangle { id: headRule; anchors.top: header.bottom; width: parent.width; height: 1; color: Style.line }

        ScrollView {
            id: scroller
            anchors.top: headRule.bottom
            anchors.bottom: footRule.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 32
            anchors.rightMargin: 20
            anchors.topMargin: 24
            anchors.bottomMargin: 24
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                id: content
                width: scroller.availableWidth - 12
                spacing: 14

                // Loadouts: saved sets of model, rules, cycles, and orders.
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    FieldLabel {
                        height: 28
                        verticalAlignment: Text.AlignVCenter
                        rightPadding: 6
                        text: qsTr("Loadout")
                    }
                    Repeater {
                        model: ops.loadouts
                        delegate: Rectangle {
                            id: loadoutChip
                            required property var modelData
                            width: loadoutRow.implicitWidth + 20
                            height: 28
                            color: loadoutHover.hovered ? Style.raised : "transparent"
                            border.color: loadoutHover.hovered ? Style.lineStrong : Style.line
                            radius: Math.min(2, theme.radius)
                            Row {
                                id: loadoutRow
                                anchors.centerIn: parent
                                spacing: 8
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: loadoutChip.modelData.name
                                    color: Style.text
                                    font.family: Style.body
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                }
                                Text {
                                    text: (loadoutChip.modelData.model || qsTr("default")) + " · " + loadoutChip.modelData.cycles
                                    color: Style.dim
                                    font.family: Style.mono
                                    font.variableAxes: Style.narrow
                                    font.pixelSize: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    visible: loadoutHover.hovered
                                    text: "✕"
                                    color: removeHover.hovered ? Style.danger : Style.dim
                                    font.family: Style.mono
                                    font.variableAxes: Style.narrow
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
                        leftPadding: 6
                        visible: !panel.savingLoadout
                        text: qsTr("+ Save current")
                        color: saveHover.hovered ? theme.accent : Style.dim
                        font.family: Style.body
                        font.pixelSize: 12
                        font.weight: Font.Medium
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
                        font.family: Style.body
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

                // Recipes: ready-made objectives with their criteria and loadout.
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: panel.editing < 0
                    FieldLabel {
                        height: 28
                        verticalAlignment: Text.AlignVCenter
                        rightPadding: 6
                        text: qsTr("Recipe")
                    }
                    Repeater {
                        model: ops.recipes
                        delegate: Rectangle {
                            id: recipeChip
                            required property var modelData
                            width: recipeLabel.implicitWidth + 20 + (recipeChip.modelData.builtin ? 0 : 16)
                            height: 28
                            color: recipeHover.hovered ? Style.raised : "transparent"
                            border.color: recipeHover.hovered ? Style.lineStrong : Style.line
                            radius: Math.min(2, theme.radius)
                            Text {
                                id: recipeLabel
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: recipeChip.modelData.name
                                color: Style.text2
                                font.family: Style.body
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }
                            Text {
                                visible: !recipeChip.modelData.builtin && recipeHover.hovered
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: "✕"
                                color: recipeRemove.hovered ? Style.danger : Style.dim
                                font.pixelSize: 11
                                HoverHandler { id: recipeRemove }
                                TapHandler { onTapped: ops.removeRecipe(recipeChip.modelData.name) }
                            }
                            HoverHandler { id: recipeHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: panel.applyRecipe(recipeChip.modelData) }
                            ToolTip.visible: recipeHover.hovered
                            ToolTip.delay: 500
                            ToolTip.text: recipeChip.modelData.objective
                        }
                    }
                    Text {
                        height: 28
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 6
                        visible: !panel.savingRecipe && objective.text.trim().length > 0
                        text: qsTr("+ Save as recipe")
                        color: recipeSaveHover.hovered ? theme.accent : Style.dim
                        font.family: Style.body
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        HoverHandler { id: recipeSaveHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { panel.savingRecipe = true; recipeName.forceActiveFocus() } }
                    }
                    TextField {
                        id: recipeName
                        visible: panel.savingRecipe
                        width: 180
                        height: 34
                        topPadding: 4
                        bottomPadding: 4
                        placeholderText: qsTr("Recipe name")
                        font.family: Style.body
                        font.pixelSize: 12
                        onAccepted: {
                            if (text.trim().length > 0)
                                ops.saveRecipe({ name: text, objective: objective.text, criteria: criteriaField.text,
                                                 loadout: Prefs.defaultLoadout })
                            text = ""
                            panel.savingRecipe = false
                        }
                        Keys.onEscapePressed: { text = ""; panel.savingRecipe = false }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 10
                    TextField {
                        id: codename
                        Layout.fillWidth: true
                        placeholderText: qsTr("Codename")
                        // A callsign: wide mono. It's stored in capitals.
                        font.family: Style.mono
                        font.variableAxes: Style.wide
                        font.pixelSize: 16
                        font.letterSpacing: -0.3
                        // A callsign, so it's typed in capitals; the field's own
                        // label stays in sentence case.
                        onTextEdited: { const at = cursorPosition; const upper = text.toUpperCase(); if (upper !== text) { text = upper; cursorPosition = at } }
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
                        font.variableAxes: Style.narrow
                        font.pixelSize: 13
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
                    Layout.preferredHeight: 132
                    TextArea {
                        id: objective
                        placeholderText: qsTr("Objective: what should the fireteam build or fix?")
                        wrapMode: TextArea.Wrap
                        font.family: Style.body
                        font.pixelSize: 14
                    }
                }

                SectionLabel { Layout.fillWidth: true; Layout.topMargin: 12; text: qsTr("Cycles") }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    TacticalButton { implicitWidth: 40; text: "−"; enabled: panel.cycles > panel.minimumCycles; onClicked: panel.cycles-- }
                    Text {
                        Layout.preferredWidth: 72
                        horizontalAlignment: Text.AlignHCenter
                        text: Style.pad(panel.cycles)
                        color: Style.text
                        font.family: Style.mono
                        font.variableAxes: Style.figure
                        font.pixelSize: 30
                        font.features: { "tnum": 1 }
                    }
                    TacticalButton { implicitWidth: 40; text: "+"; enabled: panel.cycles < 20; onClicked: panel.cycles++ }
                    Note {
                        Layout.fillWidth: true
                        Layout.leftMargin: 20
                        text: qsTr("Each cycle is one Claude Code run that picks up where the last left off and files an HTML debrief.")
                    }
                }

                SectionLabel { Layout.fillWidth: true; Layout.topMargin: 12; text: qsTr("Rules of engagement") }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
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
                            radius: Math.min(2, theme.radius)
                            color: chosen ? Style.wash : cardHover.hovered ? Style.raised : "transparent"
                            border.color: chosen ? Style.lineStrong : Style.line
                            // The chosen card's leading rule, in its tone.
                            Rectangle { visible: card.chosen; width: 2; height: parent.height; color: card.tone }
                            ColumnLayout {
                                id: cardText
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 14
                                spacing: 6
                                RowLayout {
                                    spacing: 8
                                    Rectangle {
                                        implicitWidth: 6; implicitHeight: 6
                                        Layout.alignment: Qt.AlignVCenter
                                        color: card.chosen ? card.tone : Style.faint
                                    }
                                    Text {
                                        text: card.modelData.title
                                        color: Style.text
                                        font.family: Style.body
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: card.modelData.body
                                    wrapMode: Text.Wrap
                                    lineHeight: 1.3
                                    color: card.chosen ? Style.text2 : Style.dim
                                    font.family: Style.body
                                    font.pixelSize: 12
                                }
                            }
                            HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: panel.roe = card.modelData.key }
                        }
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 24
                    RowLayout {
                        spacing: 12
                        FieldLabel { text: qsTr("Model") }
                        ComboBox {
                            id: model
                            Layout.preferredWidth: 200
                            font.family: Style.body
                            font.pixelSize: 13
                            model: [qsTr("Account default"), "opus", "sonnet", "haiku"]
                        }
                    }
                    RowLayout {
                        spacing: 12
                        FieldLabel { text: qsTr("Hand off at") }
                        ComboBox {
                            id: handoff
                            Layout.preferredWidth: 150
                            font.family: Style.body
                            font.pixelSize: 13
                            // Context sizes at which the next cycle moves to a fresh session.
                            readonly property var limits: [150000, 250000, 400000, 600000, 0]
                            model: ["150k", "250k", "400k", "600k", qsTr("Never")]
                            currentIndex: 1
                        }
                    }
                }

                SectionLabel { Layout.fillWidth: true; Layout.topMargin: 12; text: qsTr("Deployment") }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Switch {
                        id: worktreeSwitch
                        Layout.alignment: Qt.AlignTop
                        checked: panel.useWorktree && panel.worktreeAvailable
                        enabled: panel.worktreeAvailable && !panel.worktreeLocked
                        onToggled: panel.useWorktree = checked
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 10
                        spacing: 3
                        Text {
                            text: qsTr("Own worktree")
                            color: worktreeSwitch.enabled ? Style.text : Style.dim
                            font.family: Style.body
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }
                        Note {
                            Layout.fillWidth: true
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
                    font.family: Style.body
                    font.pixelSize: 12
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    FieldLabel { text: qsTr("Overwatch") }
                    ComboBox {
                        id: overwatchBox
                        Layout.preferredWidth: 180
                        font.family: Style.body
                        font.pixelSize: 13
                        readonly property var keys: ["off", "review", "fix"]
                        model: [qsTr("Off"), qsTr("Review"), qsTr("Review and fix")]
                    }
                    Note {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        text: overwatchBox.currentIndex === 0 ? qsTr("No review; the operation completes after its last cycle.")
                            : overwatchBox.currentIndex === 1 ? qsTr("After the last cycle, a separate read-only session grades the work against the objective.")
                            : qsTr("As Review, and if it falls short, one more cycle fixes the findings before a second review.")
                    }
                }
                TextField {
                    id: standingField
                    Layout.fillWidth: true
                    placeholderText: qsTr("Standing orders for every cycle (optional), e.g. Run the tests before finishing.")
                    font.family: Style.body
                    font.pixelSize: 13
                }

                SectionLabel { Layout.fillWidth: true; Layout.topMargin: 12; text: qsTr("Proof"); detail: qsTr("checked by Fireteam, not the agent") }
                // Gates: found in the project, toggled, or added.
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    FieldLabel {
                        height: 34
                        verticalAlignment: Text.AlignVCenter
                        rightPadding: 6
                        text: qsTr("Gates")
                    }
                    Repeater {
                        model: panel.gates
                        delegate: Rectangle {
                            id: gateChip
                            required property var modelData
                            required property int index
                            readonly property bool on: modelData.enabled !== false
                            width: gateRow.implicitWidth + 20
                            height: 34
                            color: on ? Style.wash : gateHover.hovered ? Style.raised : "transparent"
                            border.color: on ? Style.lineStrong : Style.line
                            radius: Math.min(2, theme.radius)
                            Row {
                                id: gateRow
                                anchors.centerIn: parent
                                spacing: 7
                                Text {
                                    text: gateChip.on ? "✓" : "○"
                                    color: gateChip.on ? theme.accent : Style.faint
                                    font.family: Style.mono
                                    font.variableAxes: Style.narrow
                                    font.pixelSize: 11
                                }
                                Text {
                                    text: gateChip.modelData.command
                                    color: gateChip.on ? Style.text : Style.dim
                                    font.family: Style.mono
                                    font.variableAxes: Style.narrow
                                    font.pixelSize: 11
                                }
                            }
                            HoverHandler { id: gateHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: panel.toggleGate(gateChip.index) }
                        }
                    }
                    TextField {
                        id: newGate
                        width: panel.gates.length === 0 ? 300 : 200
                        height: 34
                        topPadding: 4
                        bottomPadding: 4
                        placeholderText: panel.gates.length === 0 ? qsTr("None found; add one, e.g. make test") : qsTr("+ Add a gate")
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                        font.pixelSize: 11
                        onAccepted: { panel.addGate(text); text = "" }
                    }
                }
                ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 76
                    TextArea {
                        id: criteriaField
                        placeholderText: qsTr("Acceptance criteria, one per line (optional), e.g. Exports open in Excel")
                        wrapMode: TextArea.Wrap
                        font.family: Style.body
                        font.pixelSize: 13
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Switch {
                        checked: panel.previewOn
                        enabled: ops.browserAvailable
                        onToggled: panel.previewOn = checked
                    }
                    Text {
                        text: ops.browserAvailable ? qsTr("Preview screenshot") : qsTr("Preview screenshot (needs Chromium)")
                        color: ops.browserAvailable ? Style.text : Style.dim
                        font.family: Style.body
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    TextField {
                        id: previewCommand
                        visible: panel.previewOn
                        Layout.fillWidth: true
                        Layout.preferredWidth: 2
                        placeholderText: qsTr("Start command, e.g. npm run dev")
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                        font.pixelSize: 11
                    }
                    TextField {
                        id: previewUrl
                        visible: panel.previewOn
                        Layout.fillWidth: true
                        Layout.preferredWidth: 2
                        placeholderText: qsTr("Address, e.g. http://localhost:5173")
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                        font.pixelSize: 11
                    }
                    Item { visible: !panel.previewOn; Layout.fillWidth: true }
                }
            }
        }

        Rectangle { id: footRule; anchors.bottom: footer.top; width: parent.width; height: 1; color: Style.line }

        // Footer: any error, then the buttons, always in view.
        ColumnLayout {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: 0
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 14
                Layout.leftMargin: 32
                Layout.rightMargin: 32
                visible: panel.error.length > 0
                text: "⚠ " + panel.error
                wrapMode: Text.Wrap
                color: Style.danger
                font.family: Style.body
                font.pixelSize: 13
                font.weight: Font.Medium
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 16
                Layout.bottomMargin: 16
                Layout.leftMargin: 32
                Layout.rightMargin: 32
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

    Shortcut {
        enabled: panel.visible
        sequences: ["Ctrl+Return", "Ctrl+Enter"]
        context: Qt.ApplicationShortcut
        onActivated: panel.submit(true)
    }
}
