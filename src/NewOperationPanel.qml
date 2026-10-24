import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// The briefing screen for a new operation.
Item {
    id: panel
    visible: false
    signal planned(bool deployNow)

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius

    property string error: ""
    property int cycles: 3
    property string roe: "restricted"

    function open() {
        codename.text = ops.suggestCodename()
        objective.text = ""
        error = ""
        cycles = 3
        roe = "restricted"
        visible = true
        enter.restart()
        if (directory.text.length === 0)
            directory.forceActiveFocus()
        else
            objective.forceActiveFocus()
    }
    function close() { visible = false }
    function submit(deployNow) {
        error = ops.validate(directory.text, objective.text)
        if (error.length > 0)
            return
        ops.create(codename.text, directory.text, objective.text, cycles, roe,
                   model.currentIndex === 0 ? "" : model.currentText)
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
        TapHandler { onTapped: panel.close() }
    }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(760, parent.width - 48)
        height: Math.min(content.implicitHeight + 64, parent.height - 48)
        color: Qt.rgba(0.04, 0.05, 0.065, 0.97)
        border.color: Style.line
        radius: theme.radius
        // Swallow taps so they don't reach the dismissing backdrop.
        TapHandler {}

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
                        font.letterSpacing: 4
                        font.capitalization: Font.AllUppercase
                    }
                    Text {
                        text: qsTr("Plan operation")
                        color: Style.text
                        font.family: Style.display
                        font.pixelSize: 34
                        font.weight: Font.Black
                        font.letterSpacing: 5
                        font.capitalization: Font.AllUppercase
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
                        font.letterSpacing: 3
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
                        placeholderText: qsTr("Project directory")
                        font.family: Style.mono
                    }
                    TacticalButton {
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
                    TacticalButton { text: "−"; enabled: panel.cycles > 1; onClicked: panel.cycles-- }
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
                            { key: "free", title: qsTr("Weapons free"),
                              body: qsTr("Full autonomy: runs any command without asking. Only for projects you can afford to have changed.") }
                        ]
                        delegate: Rectangle {
                            id: card
                            required property var modelData
                            readonly property bool chosen: panel.roe === modelData.key
                            readonly property color tone: modelData.key === "free" ? Style.danger : theme.accent
                            Layout.fillWidth: true
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
                                    font.letterSpacing: 3
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
                        font.letterSpacing: 3
                        font.capitalization: Font.AllUppercase
                    }
                    ComboBox {
                        id: model
                        Layout.preferredWidth: 220
                        model: [qsTr("Account default"), "opus", "sonnet", "haiku"]
                    }
                    Item { Layout.fillWidth: true }
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
                    TacticalButton { text: qsTr("Hold at standby"); onClicked: panel.submit(false) }
                    TacticalButton { text: qsTr("Deploy"); key: "Ctrl+Enter"; primary: true; onClicked: panel.submit(true) }
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
