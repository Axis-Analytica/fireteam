import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Options and About, as two tabs of one sheet: how the board behaves, what new
// operations start from, where Fireteam keeps things, and what it is.
Item {
    id: panel
    visible: false
    property string tab: "options"
    signal terminalRequested()
    signal controlsRequested()

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius
    Material.background: Style.panel

    function open(which) {
        tab = which || "options"
        visible = true
        enter.restart()
        scroller.ScrollBar.vertical.position = 0
    }
    function close() { visible = false }

    // A setting: its name and what it does on the left, its control on the right.
    component OptionRow: RowLayout {
        id: row
        property string label
        property string hint
        default property alias control: slot.data
        Layout.fillWidth: true
        spacing: 20
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
                Layout.fillWidth: true
                text: row.label
                wrapMode: Text.Wrap
                color: Style.text
                font.family: Style.body
                font.pixelSize: 14
                font.weight: Font.Medium
            }
            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: row.hint
                wrapMode: Text.Wrap
                color: Style.dim
                font.family: Style.body
                font.pixelSize: 12
                lineHeight: 1.15
            }
        }
        Item {
            id: slot
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
        }
    }
    // A fact on the About tab: a muted name and a value set as data.
    component Fact: RowLayout {
        id: fact
        property string label
        property string value
        property color tone: Style.text2
        property bool link: false
        signal activated()
        Layout.fillWidth: true
        spacing: 16
        Text {
            Layout.preferredWidth: 140
            text: fact.label
            color: Style.dim
            font.family: Style.body
            font.pixelSize: 13
        }
        Text {
            Layout.fillWidth: true
            text: fact.value
            elide: Text.ElideMiddle
            color: fact.link && factHover.hovered ? theme.accent : fact.tone
            font.family: Style.mono
            font.variableAxes: Style.narrow
            font.pixelSize: 12
            font.underline: fact.link && factHover.hovered
            HoverHandler { id: factHover; enabled: fact.link; cursorShape: Qt.PointingHandCursor }
            TapHandler { enabled: fact.link; onTapped: fact.activated() }
        }
    }
    component Rule: Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Style.bg.r, Style.bg.g, Style.bg.b, 0.86)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: panel.close() }
    }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(820, parent.width - 48)
        height: Math.min(760, parent.height - 48)
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
            anchors.margins: 28
            spacing: 16

            // The two tabs are the title.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Text {
                    text: "# " + qsTr("Base camp").toLowerCase() + " // fireteam " + Qt.application.version
                    color: Style.dim
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 11
                }
                Row {
                    spacing: 28
                    Repeater {
                        model: [{ key: "options", label: qsTr("Options") }, { key: "about", label: qsTr("About") }]
                        delegate: Text {
                            id: tabLabel
                            required property var modelData
                            readonly property bool chosen: panel.tab === modelData.key
                            text: modelData.label
                            color: chosen ? Style.text : tabHover.hovered ? Style.text2 : Style.faint
                            font.family: Style.display
                            font.pixelSize: 28
                            font.weight: Font.DemiBold
                            font.letterSpacing: -0.6
                            bottomPadding: 8
                            Rectangle {
                                visible: tabLabel.chosen
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 2
                                color: theme.accent
                            }
                            HoverHandler { id: tabHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: panel.tab = tabLabel.modelData.key }
                        }
                    }
                }
            }
            Rule {}

            ScrollView {
                id: scroller
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                clip: true

                ColumnLayout {
                    width: scroller.availableWidth - 12
                    spacing: 14

                    // ── Options ──────────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: panel.tab === "options"
                        spacing: 14

                        SectionLabel { Layout.fillWidth: true; text: qsTr("Board") }
                        OptionRow {
                            label: qsTr("Interface sounds")
                            hint: qsTr("Short sounds for hovering, selecting, deploying, finishing and failing.")
                            Switch { checked: Sfx.enabled; onToggled: if (checked !== Sfx.enabled) Sfx.toggle() }
                        }
                        OptionRow {
                            label: qsTr("Insertion screen")
                            hint: qsTr("Play the short insertion screen when an operation deploys.")
                            Switch { checked: Prefs.insertion; onToggled: Prefs.insertion = checked }
                        }
                        OptionRow {
                            label: qsTr("Backdrop motion")
                            hint: qsTr("Dust and embers drifting behind the board. Off keeps it still.")
                            Switch { checked: Prefs.motion; onToggled: Prefs.motion = checked }
                        }
                        OptionRow {
                            label: qsTr("Squad size")
                            hint: qsTr("How many operations can be deployed at once; the rest wait in the queue.")
                            RowLayout {
                                spacing: 6
                                TacticalButton {
                                    text: "−"
                                    implicitWidth: 40
                                    onClicked: ops.maxDeployed = ops.maxDeployed === 0 ? 12 : Math.max(1, ops.maxDeployed - 1)
                                }
                                Text {
                                    Layout.preferredWidth: 56
                                    horizontalAlignment: Text.AlignHCenter
                                    text: ops.maxDeployed === 0 ? "∞" : Style.pad(ops.maxDeployed)
                                    color: Style.text
                                    font.family: Style.mono
                                    font.variableAxes: Style.figure
                                    font.pixelSize: 24
                                }
                                TacticalButton {
                                    text: "+"
                                    implicitWidth: 40
                                    onClicked: ops.maxDeployed = ops.maxDeployed === 0 || ops.maxDeployed >= 12 ? 0 : ops.maxDeployed + 1
                                }
                            }
                        }

                        SectionLabel { Layout.fillWidth: true; Layout.topMargin: 10; text: qsTr("New operations") }
                        OptionRow {
                            label: qsTr("Start from loadout")
                            hint: qsTr("A new briefing starts with this loadout's model, cycles, rules of engagement and orders.")
                            ComboBox {
                                id: loadoutBox
                                implicitWidth: 200
                                font.family: Style.body
                                Material.background: Style.bg
                                readonly property var names: [""].concat(ops.loadouts.map(l => l.name))
                                model: names.map(n => n.length > 0 ? n : qsTr("None"))
                                currentIndex: Math.max(0, names.indexOf(Prefs.defaultLoadout))
                                onActivated: (index) => Prefs.defaultLoadout = names[index]
                            }
                        }
                        OptionRow {
                            label: qsTr("After-action reviews")
                            hint: qsTr("After each finished operation, a short read-only haiku session adds what it learned.")
                            Switch { checked: ops.afterAction; onToggled: ops.afterAction = checked }
                        }
                        OptionRow {
                            label: qsTr("Saved loadouts")
                            hint: qsTr("Save the current settings as a loadout from the briefing.")
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 8
                            Repeater {
                                model: ops.loadouts
                                delegate: Rectangle {
                                    id: loadoutChip
                                    required property var modelData
                                    implicitWidth: chipRow.implicitWidth + 20
                                    implicitHeight: 30
                                    color: Style.bg
                                    border.color: Style.line
                                    radius: Math.min(2, theme.radius)
                                    RowLayout {
                                        id: chipRow
                                        anchors.centerIn: parent
                                        spacing: 8
                                        Text {
                                            text: loadoutChip.modelData.name
                                            color: Style.text
                                            font.family: Style.body
                                            font.pixelSize: 13
                                            font.weight: Font.Medium
                                        }
                                        Text {
                                            text: (loadoutChip.modelData.model || qsTr("default model")) + " · " + loadoutChip.modelData.cycles
                                            color: Style.dim
                                            font.family: Style.mono
                                            font.variableAxes: Style.narrow
                                            font.pixelSize: 11
                                        }
                                        Text {
                                            text: "✕"
                                            color: removeHover.hovered ? Style.danger : Style.faint
                                            font.pixelSize: 12
                                            HoverHandler { id: removeHover; cursorShape: Qt.PointingHandCursor }
                                            TapHandler {
                                                onTapped: {
                                                    if (Prefs.defaultLoadout === loadoutChip.modelData.name)
                                                        Prefs.defaultLoadout = ""
                                                    ops.removeLoadout(loadoutChip.modelData.name)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        SectionLabel { Layout.fillWidth: true; Layout.topMargin: 10; text: qsTr("Knowledge graphs") }
                        OptionRow {
                            label: ops.graphify.length > 0 ? qsTr("graphify is installed")
                                 : ops.graphifyInstall === "installing" ? qsTr("Installing graphify…")
                                 : qsTr("graphify isn't installed")
                            hint: ops.graphify.length > 0 ? ops.graphify
                                : ops.graphifyInstall.length > 0 && ops.graphifyInstall !== "installing" ? ops.graphifyInstall
                                : qsTr("It maps a project's code locally, with no API key. Fireteam installs it in its own folder.")
                            TacticalButton {
                                visible: ops.graphify.length === 0
                                enabled: ops.graphifyInstall !== "installing"
                                text: qsTr("Install")
                                onClicked: ops.installGraphify()
                            }
                        }
                        OptionRow {
                            label: qsTr("Map projects automatically")
                            hint: qsTr("Map a project when its first operation deploys, and redraw the map after each cycle and extraction. Agents get a summary of the map and may query it.")
                            Switch { checked: ops.graphsAuto; onToggled: ops.graphsAuto = checked }
                        }

                        SectionLabel { Layout.fillWidth: true; Layout.topMargin: 10; text: qsTr("Field terminal") }
                        OptionRow {
                            label: !terminal ? "" : terminal.enabled
                                   ? (terminal.listening ? qsTr("On · listening") : qsTr("On · not listening"))
                                   : qsTr("Off")
                            hint: qsTr("Steer operations from your phone: comms, questions, approvals and orders.")
                            TacticalButton { text: qsTr("Set up"); key: "P"; onClicked: panel.terminalRequested() }
                        }

                        SectionLabel { Layout.fillWidth: true; Layout.topMargin: 10; text: qsTr("Data") }
                        OptionRow {
                            label: qsTr("Data folder")
                            hint: ops.dataDirectory
                            TacticalButton { text: qsTr("Open"); onClicked: Qt.openUrlExternally("file://" + ops.dataDirectory) }
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            text: qsTr("The look follows your Omarchy theme and the language follows Omarchy's, both live.")
                            wrapMode: Text.Wrap
                            color: Style.faint
                            font.family: Style.body
                            font.pixelSize: 12
                        }
                    }

                    // ── About ────────────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: panel.tab === "about"
                        spacing: 14

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 14
                            Rectangle { implicitWidth: 14; implicitHeight: 14; color: theme.accent; Layout.alignment: Qt.AlignVCenter }
                            Text {
                                text: "FIRETEAM"
                                color: Style.text
                                font.family: Style.mono
                                font.variableAxes: Style.wide
                                font.pixelSize: 40
                                font.letterSpacing: -1
                            }
                            Item { Layout.fillWidth: true }
                            Figure { value: Qt.application.version; comment: qsTr("Version").toLowerCase(); size: 26 }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Base camp for Claude Code agents: plan operations, send fireteams in to work through cycles, and watch the work land, with proof.")
                            wrapMode: Text.Wrap
                            color: Style.text2
                            font.family: Style.body
                            font.pixelSize: 15
                            lineHeight: 1.25
                        }

                        SectionLabel { Layout.fillWidth: true; Layout.topMargin: 8; text: qsTr("This machine") }
                        Fact {
                            label: qsTr("Claude link")
                            value: ops.linkStatus === "online" ? qsTr("Online · %1").arg(ops.account)
                                 : ops.linkStatus === "checking" ? qsTr("Checking…")
                                 : ops.linkStatus === "missing" ? qsTr("claude not installed")
                                 : qsTr("Not logged in: run claude to sign in")
                            tone: ops.linkStatus === "online" ? Style.good : ops.linkStatus === "checking" ? Style.amber : Style.danger
                        }
                        Rule {}
                        Fact { label: qsTr("Claude Code"); value: ops.claudePath }
                        Rule {}
                        Fact { label: qsTr("Data"); value: ops.dataDirectory; link: true; onActivated: Qt.openUrlExternally("file://" + ops.dataDirectory) }
                        Rule {}
                        Fact { label: qsTr("Chromium"); value: ops.browserAvailable ? qsTr("Found: preview screenshots on") : qsTr("Not found: preview screenshots off") }

                        SectionLabel { Layout.fillWidth: true; Layout.topMargin: 8; text: qsTr("Project") }
                        Fact {
                            label: qsTr("Source")
                            value: "github.com/Axis-Analytica/fireteam"
                            link: true
                            onActivated: Qt.openUrlExternally("https://github.com/Axis-Analytica/fireteam")
                        }
                        Rule {}
                        Fact {
                            label: qsTr("Releases")
                            value: "github.com/Axis-Analytica/fireteam/releases"
                            link: true
                            onActivated: Qt.openUrlExternally("https://github.com/Axis-Analytica/fireteam/releases")
                        }
                        Rule {}
                        Fact { label: qsTr("Licence"); value: "MIT" }

                        SectionLabel { Layout.fillWidth: true; Layout.topMargin: 8; text: qsTr("Credits") }
                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Martian Mono by Evil Martians, and Red Hat Text and Display by Red Hat, under the SIL Open Font License. The look draws on the Terminal and Furrow themes of Hallmark. Theme following and the portal file picker follow Omacut. Built with Qt, for Omarchy, on Claude Code.")
                            wrapMode: Text.Wrap
                            color: Style.dim
                            font.family: Style.body
                            font.pixelSize: 13
                            lineHeight: 1.25
                        }
                    }
                }
            }

            Rule {}
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                TacticalButton { text: qsTr("Close"); key: "Esc"; onClicked: panel.close() }
                Item { Layout.fillWidth: true }
                TacticalButton { text: qsTr("Controls"); key: "?"; onClicked: panel.controlsRequested() }
            }
        }
    }
}
