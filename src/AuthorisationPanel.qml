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
        color: Qt.rgba(Style.bg.r, Style.bg.g, Style.bg.b, 0.86)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: panel.close() }
    }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(820, parent.width - 48)
        height: Math.min(head.implicitHeight + column.implicitHeight + foot.implicitHeight + 2 + 28 + 20 + 40 + 32,
                         parent.height - 48)
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

            ColumnLayout {
                id: head
                Layout.fillWidth: true
                Layout.margins: 32
                Layout.topMargin: 28
                Layout.bottomMargin: 20
                spacing: 4
                Text {
                    Layout.fillWidth: true
                    text: panel.op ? "# " + qsTr("Authorisation // %1").arg(panel.op.codename) : ""
                    elide: Text.ElideRight
                    color: Style.dim
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 11
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.topMargin: 2
                        visible: panel.op !== null && panel.op.requests.length > 0
                        implicitWidth: 8; implicitHeight: 8
                        color: Style.amber
                    }
                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Requests to fire")
                        elide: Text.ElideRight
                        color: Style.text
                        font.family: Style.display
                        font.pixelSize: 28
                        font.weight: Font.DemiBold
                        font.letterSpacing: -0.6
                    }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: panel.op ? Style.pad(panel.op.requests.length) : ""
                        color: Style.text2
                        font.family: Style.mono
                        font.variableAxes: Style.figure
                        font.pixelSize: 22
                        font.features: { "tnum": 1 }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    text: qsTr("Under restricted ROE, Claude Code refuses any command your permission settings don't already allow. Approved commands work from the agent's next cycle, and it's told they're cleared.")
                    wrapMode: Text.Wrap
                    color: Style.text2
                    font.family: Style.body
                    font.pixelSize: 13
                    lineHeight: 1.15
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }

            ScrollView {
                id: scroller
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 32
                Layout.rightMargin: 32
                Layout.topMargin: 20
                Layout.bottomMargin: 20
                contentWidth: availableWidth
                clip: true

                ColumnLayout {
                    id: column
                    width: scroller.availableWidth
                    spacing: 12

                    SectionLabel {
                        Layout.fillWidth: true
                        text: qsTr("Waiting")
                        detail: panel.op ? "" + panel.op.requests.length : ""
                    }
                    Text {
                        visible: panel.op !== null && panel.op.requests.length === 0
                        text: qsTr("Nothing waiting. Refused commands land here.")
                        color: Style.dim
                        font.family: Style.body
                        font.pixelSize: 13
                    }
                    Repeater {
                        model: panel.op ? panel.op.requests : []
                        delegate: Rectangle {
                            id: request
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            implicitHeight: requestColumn.implicitHeight + 28
                            color: Style.bg
                            border.color: Style.line
                            radius: Math.min(2, theme.radius)

                            ColumnLayout {
                                id: requestColumn
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 14
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 10
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Text {
                                        Layout.alignment: Qt.AlignTop
                                        text: "$"
                                        color: theme.accent
                                        font.family: Style.mono
                                        font.variableAxes: Style.narrow
                                        font.pixelSize: 13
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignTop
                                        text: request.modelData.summary
                                        wrapMode: Text.WrapAnywhere
                                        maximumLineCount: 3
                                        elide: Text.ElideRight
                                        color: Style.text
                                        font.family: Style.mono
                                        font.variableAxes: Style.narrow
                                        font.pixelSize: 13
                                        textFormat: Text.PlainText
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignTop
                                        Layout.topMargin: 1
                                        text: qsTr("cycle %1 · %2").arg(request.modelData.cycle).arg(request.modelData.time)
                                        color: Style.dim
                                        font.family: Style.mono
                                        font.variableAxes: Style.narrow
                                        font.pixelSize: 11
                                    }
                                }
                                // The rule to approve it with, and the verdict,
                                // on one line when there's room.
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    // The rule to approve it with: the command family,
                                    // or exactly this command.
                                    Flow {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 8
                                        Repeater {
                                            model: request.modelData.choices
                                            delegate: Rectangle {
                                                id: ruleChip
                                                required property var modelData
                                                required property int index
                                                readonly property bool chosen: panel.choice(request.index) === index
                                                width: Math.min(ruleText.implicitWidth + 24, Math.max(80, requestColumn.width - 200))
                                                height: 28
                                                color: chosen ? Style.wash : ruleHover.hovered ? Style.raised : Style.panel
                                                border.color: chosen ? theme.accent : Style.line
                                                radius: Math.min(2, theme.radius)
                                                Text {
                                                    id: ruleText
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    x: 12
                                                    width: parent.width - 24
                                                    text: (ruleChip.index === 0 && request.modelData.choices.length > 1 ? qsTr("Any  ") : ruleChip.index === 1 ? qsTr("Only  ") : "")
                                                          + ruleChip.modelData.join("  +  ")
                                                    elide: Text.ElideRight
                                                    color: ruleChip.chosen ? Style.text : Style.dim
                                                    font.family: Style.mono
                                                    font.variableAxes: Style.narrow
                                                    font.pixelSize: 11
                                                }
                                                HoverHandler { id: ruleHover; cursorShape: Qt.PointingHandCursor }
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
                                    TacticalButton {
                                        Layout.alignment: Qt.AlignBottom
                                        text: qsTr("Deny")
                                        danger: true
                                        onClicked: ops.deny(panel.row, request.index)
                                    }
                                    TacticalButton {
                                        Layout.alignment: Qt.AlignBottom
                                        text: qsTr("Approve")
                                        primary: true
                                        onClicked: ops.approve(panel.row, request.index, panel.choice(request.index), panel.projectWide)
                                    }
                                }
                            }
                        }
                    }

                    CheckBox {
                        Layout.fillWidth: true
                        Layout.topMargin: -4
                        Layout.leftMargin: -8
                        checked: panel.projectWide
                        onToggled: panel.projectWide = checked
                        text: qsTr("Also allow in this project for every Claude session (writes .claude/settings.local.json)")
                        font.family: Style.body
                        font.pixelSize: 12
                        contentItem: Text {
                            leftPadding: parent.indicator.width + parent.spacing
                            verticalAlignment: Text.AlignVCenter
                            text: parent.text
                            wrapMode: Text.Wrap
                            color: Style.text2
                            font: parent.font
                        }
                    }

                    SectionLabel {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
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
                                width: Math.min(grantedRow.implicitWidth + 24, column.width)
                                height: 28
                                color: Style.panel
                                border.color: revokeHover.hovered ? Style.danger : Style.line
                                radius: Math.min(2, theme.radius)
                                Row {
                                    id: grantedRow
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: 10
                                    spacing: 8
                                    Rectangle { width: 6; height: 6; color: Style.good; anchors.verticalCenter: parent.verticalCenter }
                                    Text {
                                        width: Math.min(implicitWidth, column.width - 70)
                                        text: granted.modelData
                                        elide: Text.ElideRight
                                        color: Style.text2
                                        font.family: Style.mono
                                        font.variableAxes: Style.narrow
                                        font.pixelSize: 11
                                    }
                                    Text {
                                        text: "✕"
                                        color: revokeHover.hovered ? Style.danger : Style.dim
                                        font.family: Style.mono
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
                            color: Style.dim
                            font.family: Style.body
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
                            font.variableAxes: Style.narrow
                            font.pixelSize: 12
                            onAccepted: if (text.trim().length > 0) { ops.allow(panel.row, text, panel.projectWide); text = "" }
                        }
                        TacticalButton {
                            text: qsTr("Allow")
                            enabled: manual.text.trim().length > 0
                            onClicked: { ops.allow(panel.row, manual.text, panel.projectWide); manual.text = "" }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }

            RowLayout {
                id: foot
                Layout.fillWidth: true
                Layout.leftMargin: 32
                Layout.rightMargin: 32
                Layout.topMargin: 16
                Layout.bottomMargin: 16
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

    Shortcut {
        enabled: panel.visible && panel.op !== null && panel.op.status !== "deployed" && !manual.activeFocus
        sequences: ["Ctrl+Return", "Ctrl+Enter"]
        context: Qt.ApplicationShortcut
        onActivated: { panel.approveAll(); panel.close(); panel.resumeRequested() }
    }
}
