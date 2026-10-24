import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Commands Claude Code refused for want of approval, for the operator to
// approve or deny, and the rules already approved for the operation.
Item {
    id: panel
    visible: false
    property var op: null
    property int row: -1
    // Which suggested rule each request will be approved with, by index.
    property var choices: ({})
    property bool projectWide: false

    signal resumeRequested()

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius

    function open(target, targetRow) {
        op = target
        row = targetRow
        choices = ({})
        manual.text = ""
        visible = true
        enter.restart()
    }
    function close() { visible = false }
    function choice(index) { return choices[index] === undefined ? 0 : choices[index] }
    function approveAll() {
        for (let i = op.requests.length - 1; i >= 0; --i)
            ops.approve(row, i, choice(i), projectWide)
        choices = ({})
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.8)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: panel.close() }
    }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(820, parent.width - 48)
        height: Math.min(column.implicitHeight + 64, parent.height - 48)
        color: Qt.rgba(0.04, 0.05, 0.065, 0.97)
        border.color: Style.line
        radius: theme.radius
        // Clicks on the panel itself mustn't reach the dismissing backdrop.
        MouseArea { anchors.fill: parent }
        Rectangle { width: parent.width; height: 3; color: Style.amber }

        ParallelAnimation {
            id: enter
            NumberAnimation { target: sheet; property: "opacity"; from: 0; to: 1; duration: 160 }
            NumberAnimation { target: sheet; property: "scale"; from: 0.97; to: 1; duration: 220; easing.type: Easing.OutCubic }
        }

        ScrollView {
            anchors.fill: parent
            anchors.margins: 32
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                id: column
                width: parent.width
                spacing: 14

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: panel.op ? qsTr("Authorisation // %1").arg(panel.op.codename) : ""
                        color: Style.amber
                        font.family: Style.mono
                        font.pixelSize: 11
                        font.letterSpacing: 4 * Style.tracking
                        font.capitalization: Font.AllUppercase
                    }
                    Text {
                        text: qsTr("Requests to fire")
                        color: Style.text
                        font.family: Style.display
                        font.pixelSize: 30
                        font.weight: Font.Black
                        font.letterSpacing: 5 * Style.tracking
                        font.capitalization: Font.AllUppercase
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        text: qsTr("Under restricted ROE, Claude Code refuses any command your permission settings don't already allow. Approved commands work from the agent's next cycle, and it's told they're cleared.")
                        wrapMode: Text.Wrap
                        color: Style.dim
                        font.family: Style.display
                        font.pixelSize: 13
                    }
                }

                SectionLabel {
                    Layout.fillWidth: true
                    text: qsTr("Waiting")
                    detail: panel.op ? "" + panel.op.requests.length : ""
                }
                Text {
                    visible: panel.op !== null && panel.op.requests.length === 0
                    text: qsTr("Nothing waiting. Refused commands land here.")
                    color: Style.faint
                    font.family: Style.display
                    font.pixelSize: 13
                }
                Repeater {
                    model: panel.op ? panel.op.requests : []
                    delegate: Rectangle {
                        id: request
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: requestColumn.implicitHeight + 24
                        color: Qt.rgba(1, 1, 1, 0.03)
                        border.color: Style.line
                        radius: Math.min(4, theme.radius)
                        Rectangle { width: 3; height: parent.height; color: Style.amber }

                        ColumnLayout {
                            id: requestColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 12
                            anchors.leftMargin: 18
                            spacing: 8
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                Text {
                                    Layout.fillWidth: true
                                    text: request.modelData.summary
                                    wrapMode: Text.WrapAnywhere
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                    color: Style.text
                                    font.family: Style.mono
                                    font.pixelSize: 13
                                    textFormat: Text.PlainText
                                }
                                Text {
                                    text: qsTr("cycle %1 · %2").arg(request.modelData.cycle).arg(request.modelData.time)
                                    color: Style.faint
                                    font.family: Style.mono
                                    font.pixelSize: 11
                                }
                            }
                            // The rule to approve it with: the command family,
                            // or exactly this command.
                            Flow {
                                Layout.fillWidth: true
                                spacing: 8
                                Repeater {
                                    model: request.modelData.choices
                                    delegate: Rectangle {
                                        id: ruleChip
                                        required property var modelData
                                        required property int index
                                        readonly property bool chosen: panel.choice(request.index) === index
                                        width: ruleText.implicitWidth + 20
                                        height: 26
                                        color: chosen ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.16) : "transparent"
                                        border.color: chosen ? theme.accent : Style.line
                                        radius: Math.min(4, theme.radius)
                                        Text {
                                            id: ruleText
                                            anchors.centerIn: parent
                                            width: Math.min(implicitWidth, request.width - 80)
                                            text: (ruleChip.index === 0 && request.modelData.choices.length > 1 ? qsTr("Any  ") : ruleChip.index === 1 ? qsTr("Only  ") : "")
                                                  + ruleChip.modelData.join("  +  ")
                                            elide: Text.ElideRight
                                            color: ruleChip.chosen ? Style.text : Style.dim
                                            font.family: Style.mono
                                            font.pixelSize: 11
                                        }
                                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                                        TapHandler {
                                            onTapped: {
                                                const next = Object.assign({}, panel.choices)
                                                next[request.index] = ruleChip.index
                                                panel.choices = next
                                            }
                                        }
                                    }
                                }
                                Item { width: 1; height: 1 }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                Item { Layout.fillWidth: true }
                                TacticalButton {
                                    text: qsTr("Deny")
                                    danger: true
                                    onClicked: ops.deny(panel.row, request.index)
                                }
                                TacticalButton {
                                    text: qsTr("Approve")
                                    primary: true
                                    onClicked: ops.approve(panel.row, request.index, panel.choice(request.index), panel.projectWide)
                                }
                            }
                        }
                    }
                }

                CheckBox {
                    Layout.topMargin: -4
                    checked: panel.projectWide
                    onToggled: panel.projectWide = checked
                    text: qsTr("Also allow in this project for every Claude session (writes .claude/settings.local.json)")
                    font.family: Style.display
                    font.pixelSize: 12
                }

                SectionLabel {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    text: qsTr("Authorised for this operation")
                    detail: panel.op ? "" + panel.op.allowed.length : ""
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: panel.op ? panel.op.allowed : []
                        delegate: Rectangle {
                            id: granted
                            required property string modelData
                            width: grantedRow.implicitWidth + 20
                            height: 28
                            color: Qt.rgba(Style.good.r, Style.good.g, Style.good.b, 0.08)
                            border.color: Qt.rgba(Style.good.r, Style.good.g, Style.good.b, 0.5)
                            radius: Math.min(4, theme.radius)
                            Row {
                                id: grantedRow
                                anchors.centerIn: parent
                                spacing: 10
                                Text {
                                    text: granted.modelData
                                    color: Style.good
                                    font.family: Style.mono
                                    font.pixelSize: 11
                                }
                                Text {
                                    text: "✕"
                                    color: revokeHover.hovered ? Style.danger : Style.dim
                                    font.pixelSize: 11
                                    HoverHandler { id: revokeHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: ops.revoke(panel.row, granted.modelData) }
                                }
                            }
                        }
                    }
                    Text {
                        visible: panel.op !== null && panel.op.allowed.length === 0
                        text: qsTr("Nothing yet beyond your Claude Code settings.")
                        color: Style.faint
                        font.family: Style.display
                        font.pixelSize: 12
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    TextField {
                        id: manual
                        Layout.fillWidth: true
                        placeholderText: qsTr("Allow a command ahead of time, e.g. npm test")
                        font.family: Style.mono
                        font.pixelSize: 12
                        onAccepted: if (text.trim().length > 0) { ops.allow(panel.row, text, panel.projectWide); text = "" }
                    }
                    TacticalButton {
                        text: qsTr("Allow")
                        enabled: manual.text.trim().length > 0
                        onClicked: { ops.allow(panel.row, manual.text, panel.projectWide); manual.text = "" }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    spacing: 10
                    TacticalButton { text: qsTr("Close"); key: "Esc"; onClicked: panel.close() }
                    Item { Layout.fillWidth: true }
                    TacticalButton {
                        visible: panel.op !== null && panel.op.requests.length > 1
                        text: qsTr("Approve all")
                        onClicked: panel.approveAll()
                    }
                    TacticalButton {
                        visible: panel.op !== null && panel.op.status !== "deployed"
                        text: panel.op && panel.op.requests.length > 0 ? qsTr("Approve all and resume") : qsTr("Resume")
                        key: "Ctrl+Enter"
                        primary: true
                        onClicked: {
                            panel.approveAll()
                            panel.close()
                            panel.resumeRequested()
                        }
                    }
                }
            }
        }
    }

    Shortcut {
        enabled: panel.visible && panel.op !== null && panel.op.status !== "deployed" && !manual.activeFocus
        sequences: ["Ctrl+Return", "Ctrl+Enter"]
        context: Qt.ApplicationShortcut
        onActivated: { panel.approveAll(); panel.close(); panel.resumeRequested() }
    }
}
