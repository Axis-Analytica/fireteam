import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Everything waiting on the operator, across every operation: questions and
// live permissions (the agent is stopped on them), then refused commands
// (they wait for the next cycle). A keyboard-first triage list: J/K to move,
// Enter for the obvious answer, A always, D deny, O to open the operation.
Item {
    id: panel
    visible: false
    signal operationPicked(int row)

    // The inbox, grouped by kind: questions, permissions, refused commands.
    property var items: []
    property int selected: 0
    // Which suggested rule "Always"/"Approve" uses, per item key.
    property var choices: ({})
    // Answers being typed, per item key (kept across refreshes, not bound).
    property var drafts: ({})
    // As in the authorisation panel: approvals stay with the operation unless asked.
    property bool projectWide: false
    property string signature: ""
    readonly property var current: items.length > 0 && selected >= 0 && selected < items.length ? items[selected] : null

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius

    function open() {
        signature = ""
        choices = ({})
        drafts = ({})
        selected = 0
        refresh()
        visible = true
        enter.restart()
        triage.forceActiveFocus()
    }
    function close() { visible = false }

    function keyOf(item) {
        return item.kind + "\u001f" + item.opId + "\u001f"
             + (item.kind === "request" ? item.text + "\u001f" + item.time : item.id)
    }
    function kindRank(kind) { return kind === "question" ? 0 : kind === "prompt" ? 1 : 2 }

    function refresh() {
        const fresh = ops.inbox()
        // Group by kind, keeping the newest-first order within each.
        const grouped = fresh.map((item, i) => ({ item: item, i: i }))
            .sort((a, b) => kindRank(a.item.kind) - kindRank(b.item.kind) || a.i - b.i)
            .map(entry => entry.item)
        const sig = grouped.map(item => keyOf(item) + "\u001f" + item.row + "\u001f" + item.index).join("\u001e")
        if (sig === signature)
            return
        signature = sig
        const previous = current ? keyOf(current) : ""
        const typing = list.currentItem && list.currentItem.typing
        const scroll = list.contentY
        items = grouped
        // The same item stays selected; when it's gone (answered), the one
        // that took its place is the next.
        let next = Math.min(selected, items.length - 1)
        for (let i = 0; i < items.length; ++i)
            if (keyOf(items[i]) === previous) { next = i; break }
        selected = Math.max(0, next)
        list.currentIndex = items.length > 0 ? selected : -1
        list.contentY = scroll
        if (items.length > 0)
            list.positionViewAtIndex(selected, ListView.Contain)
        if (typing && previous.length > 0 && current && keyOf(current) === previous)
            Qt.callLater(() => { if (list.currentItem) list.currentItem.focusReply("") })
        else if (visible)
            triage.forceActiveFocus()
    }

    function select(index) {
        if (items.length === 0)
            return
        selected = Math.max(0, Math.min(items.length - 1, index))
        list.currentIndex = selected
        list.positionViewAtIndex(selected, ListView.Contain)
    }
    function chosen(item) {
        const c = choices[keyOf(item)]
        return c === undefined ? 0 : c
    }
    function choose(item, rule) {
        const next = Object.assign({}, choices)
        next[keyOf(item)] = rule
        choices = next
    }
    function cycleRule(step) {
        const item = current
        if (!item || item.kind === "question" || !item.choices || item.choices.length < 2)
            return
        const n = item.choices.length
        choose(item, (chosen(item) + step + n) % n)
    }
    function done() {
        // inboxChanged normally refreshes already; this covers a quiet model.
        refresh()
        triage.forceActiveFocus()
    }

    // The actions, as the waiting and authorisation panels make them.
    function answer(item, text) {
        if (!item || item.kind !== "question" || text.trim().length === 0)
            return
        delete drafts[keyOf(item)]
        ops.answer(item.row, item.id, text)
        done()
    }
    function primary(item) {
        if (!item)
            return
        if (item.kind === "question") {
            if (item.options && item.options.length > 0)
                answer(item, item.options[0])
            else if (list.currentItem)
                list.currentItem.focusReply("")
            return
        }
        if (item.kind === "prompt")
            ops.decide(item.row, item.id, "once")
        else
            ops.approve(item.row, item.index, chosen(item), projectWide)
        done()
    }
    function always(item) {
        if (!item || item.kind === "question")
            return
        if (item.kind === "prompt")
            ops.decide(item.row, item.id, "always", chosen(item))
        else
            ops.approve(item.row, item.index, chosen(item), projectWide)
        done()
    }
    function deny(item) {
        if (!item || item.kind === "question")
            return
        if (item.kind === "prompt")
            ops.decide(item.row, item.id, "deny")
        else
            ops.deny(item.row, item.index)
        done()
    }
    function openOperation(item) {
        if (item)
            panel.operationPicked(item.row)
    }

    function printable(event) {
        return event.text.length > 0 && event.text.charCodeAt(0) >= 32
            && (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) === 0
    }
    function kindTone(kind) { return kind === "prompt" ? Style.danger : Style.amber }
    function groupLabel(kind) {
        return kind === "question" ? qsTr("Questions") : kind === "prompt" ? qsTr("Permissions") : qsTr("Refused commands")
    }
    function groupCount(kind) {
        let n = 0
        for (let i = 0; i < items.length; ++i)
            if (items[i].kind === kind) ++n
        return n
    }

    Connections {
        target: ops
        function onInboxChanged() { if (panel.visible) panel.refresh() }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Style.bg.r, Style.bg.g, Style.bg.b, 0.86)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: panel.close() }
    }

    Rectangle {
        id: sheet
        // The top stays put as items leave, so the list doesn't jump.
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.max(24, (parent.height - 780) / 2)
        width: Math.min(860, parent.width - 48)
        // Fits the list, up to the window.
        height: Math.min(780, parent.height - 48,
                         head.implicitHeight + 48 + (panel.items.length > 0 ? list.contentHeight + 16 : 220)
                         + foot.implicitHeight + 32 + 2)
        color: Style.panel
        border.color: Style.lineStrong
        radius: theme.radius
        // Clicks on the panel itself mustn't reach the dismissing backdrop.
        MouseArea { anchors.fill: parent; onClicked: triage.forceActiveFocus() }
        Brackets { anchors.fill: parent; anchors.margins: -1; size: 12 }

        ParallelAnimation {
            id: enter
            NumberAnimation { target: sheet; property: "opacity"; from: 0; to: 1; duration: 140 }
            NumberAnimation { target: sheet; property: "anchors.topMargin"; from: Math.max(24, (panel.height - 780) / 2) + 8; to: Math.max(24, (panel.height - 780) / 2); duration: 140; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Eyebrow, title, and how much is waiting.
            RowLayout {
                id: head
                Layout.fillWidth: true
                Layout.margins: 32
                Layout.topMargin: 28
                Layout.bottomMargin: 20
                spacing: 20
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBottom
                    spacing: 4
                    Text {
                        Layout.fillWidth: true
                        text: "# inbox"
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
                            visible: panel.items.length > 0
                            implicitWidth: 8; implicitHeight: 8
                            color: Style.amber
                        }
                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Waiting on you")
                            elide: Text.ElideRight
                            color: Style.text
                            font.family: Style.display
                            font.pixelSize: 28
                            font.weight: Font.DemiBold
                            font.letterSpacing: -0.6
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        text: qsTr("Questions and permissions have stopped an agent until you answer; refused commands wait for its next cycle.")
                        wrapMode: Text.Wrap
                        color: Style.text2
                        font.family: Style.body
                        font.pixelSize: 13
                        lineHeight: 1.15
                    }
                }
                Figure {
                    Layout.alignment: Qt.AlignBottom
                    value: Style.pad(panel.items.length)
                    comment: qsTr("waiting")
                    size: 44
                    tone: panel.items.length > 0 ? Style.text : Style.faint
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Holds the keyboard while triaging; a sibling of the list so
                // focus can leave an answer field for it.
                Item {
                    id: triage
                    focus: true
                    // Typed characters (even "?") start an answer, not an app shortcut.
                    Keys.onShortcutOverride: (event) => {
                        if (panel.current && panel.current.kind === "question" && panel.printable(event)) event.accepted = true
                    }
                    Keys.onPressed: (event) => {
                        const item = panel.current
                        const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)
                        if (mods !== 0 || !item)
                            return
                        const shift = event.modifiers & Qt.ShiftModifier
                        const accept = () => { event.accepted = true }
                        switch (event.key) {
                        case Qt.Key_Down: panel.select(panel.selected + 1); return accept()
                        case Qt.Key_Up: panel.select(panel.selected - 1); return accept()
                        case Qt.Key_Home: panel.select(0); return accept()
                        case Qt.Key_End: panel.select(panel.items.length - 1); return accept()
                        case Qt.Key_Left: panel.cycleRule(-1); return accept()
                        case Qt.Key_Right: panel.cycleRule(1); return accept()
                        case Qt.Key_Tab:
                            if (item.kind === "question") { list.currentItem.focusReply(""); return accept() }
                            return
                        case Qt.Key_Return:
                        case Qt.Key_Enter: panel.primary(item); return accept()
                        }
                        if (!shift) {
                            if (event.key === Qt.Key_J) { panel.select(panel.selected + 1); return accept() }
                            if (event.key === Qt.Key_K) { panel.select(panel.selected - 1); return accept() }
                            if (event.key === Qt.Key_O) { panel.openOperation(item); return accept() }
                        }
                        if (item.kind === "question") {
                            // A number picks that option; anything else starts an answer.
                            const n = event.key - Qt.Key_1
                            if (!shift && n >= 0 && n < 9 && item.options && n < item.options.length) {
                                panel.answer(item, item.options[n])
                                return accept()
                            }
                            if (event.text.length > 0 && event.text.charCodeAt(0) >= 32 && list.currentItem) {
                                list.currentItem.focusReply(event.text)
                                return accept()
                            }
                            return
                        }
                        if (shift)
                            return
                        if (event.key === Qt.Key_A) { panel.always(item); return accept() }
                        if (event.key === Qt.Key_D) { panel.deny(item); return accept() }
                        if (event.key === Qt.Key_P && item.kind === "request") { panel.projectWide = !panel.projectWide; return accept() }
                    }

                }

                ListView {
                    id: list
                    anchors.fill: parent
                    anchors.topMargin: 8
                    anchors.bottomMargin: 8
                    visible: panel.items.length > 0
                    model: panel.items
                    clip: true
                    keyNavigationEnabled: false
                    highlightFollowsCurrentItem: false
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Item {
                        id: entry
                        required property var modelData
                        required property int index
                        readonly property bool isSelected: index === panel.selected
                        readonly property bool firstOfKind: index === 0 || panel.items[index - 1].kind !== modelData.kind
                        readonly property bool hasRules: modelData.kind !== "question" && modelData.choices
                                                         && (modelData.kind === "request" ? modelData.choices.length > 0 : modelData.choices.length > 1)
                        readonly property int rule: panel.chosen(modelData)
                        readonly property bool typing: reply.activeFocus
                        width: ListView.view.width
                        height: body.y + body.height + 1

                        function focusReply(text) {
                            if (modelData.kind !== "question")
                                return
                            if (text.length > 0)
                                reply.insert(reply.cursorPosition, text)
                            reply.forceActiveFocus()
                        }

                        // The group's heading, above its first item.
                        SectionLabel {
                            id: groupHead
                            visible: entry.firstOfKind
                            x: 32
                            y: entry.index === 0 ? 14 : 22
                            width: parent.width - 64
                            height: visible ? implicitHeight : 0
                            text: panel.groupLabel(entry.modelData.kind)
                            detail: Style.pad(panel.groupCount(entry.modelData.kind))
                        }

                        Rectangle {
                            id: body
                            x: 0
                            y: entry.firstOfKind ? groupHead.y + groupHead.height + 10 : 0
                            width: parent.width
                            height: content.implicitHeight + 28
                            color: entry.isSelected ? Style.wash : rowHover.hovered ? Style.raised : "transparent"

                            // The selected item's leading rule.
                            Rectangle {
                                visible: entry.isSelected
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 2
                                color: theme.accent
                            }
                            // Hairline between items.
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 32
                                anchors.rightMargin: 32
                                anchors.bottom: parent.bottom
                                height: 1
                                color: Style.line
                                visible: !entry.isSelected && entry.index + 1 < panel.items.length
                                         && panel.items[entry.index + 1].kind === entry.modelData.kind
                                         && entry.index + 1 !== panel.selected
                            }

                            HoverHandler { id: rowHover }
                            TapHandler {
                                onTapped: { panel.select(entry.index); triage.forceActiveFocus() }
                                onDoubleTapped: panel.openOperation(entry.modelData)
                            }

                            ColumnLayout {
                                id: content
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.leftMargin: 32
                                anchors.rightMargin: 32
                                anchors.topMargin: 14
                                spacing: 10

                                // Who's asking, what kind of thing, and when.
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Rectangle {
                                        Layout.alignment: Qt.AlignVCenter
                                        implicitWidth: 6; implicitHeight: 6
                                        color: panel.kindTone(entry.modelData.kind)
                                    }
                                    Text {
                                        Layout.maximumWidth: content.width * 0.5
                                        text: entry.modelData.codename
                                        elide: Text.ElideRight
                                        color: entry.isSelected ? Style.text : Style.text2
                                        font.family: Style.mono
                                        font.variableAxes: Style.wide
                                        font.pixelSize: 12
                                        font.letterSpacing: -0.3
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: entry.modelData.time || ""
                                        color: Style.dim
                                        font.family: Style.mono
                                        font.variableAxes: Style.narrow
                                        font.pixelSize: 11
                                    }
                                }

                                // A question in prose; a command as a prompt line.
                                Text {
                                    Layout.fillWidth: true
                                    visible: entry.modelData.kind === "question"
                                    text: entry.modelData.text || ""
                                    wrapMode: Text.Wrap
                                    maximumLineCount: entry.isSelected ? 12 : 2
                                    elide: Text.ElideRight
                                    color: Style.text
                                    font.family: Style.body
                                    font.pixelSize: 15
                                    font.weight: Font.Medium
                                    lineHeight: 1.15
                                    textFormat: Text.PlainText
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: entry.modelData.kind !== "question"
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
                                        text: entry.modelData.text || ""
                                        wrapMode: Text.WrapAnywhere
                                        maximumLineCount: entry.isSelected ? 4 : 1
                                        elide: Text.ElideRight
                                        color: Style.text
                                        font.family: Style.mono
                                        font.variableAxes: Style.narrow
                                        font.pixelSize: 13
                                        textFormat: Text.PlainText
                                    }
                                }

                                // The rule "Always" (or an approval) remembers.
                                Flow {
                                    Layout.fillWidth: true
                                    visible: entry.isSelected && entry.hasRules
                                    spacing: 8
                                    Repeater {
                                        model: entry.isSelected && entry.hasRules ? entry.modelData.choices : []
                                        delegate: Rectangle {
                                            id: ruleChip
                                            required property var modelData
                                            required property int index
                                            readonly property bool picked: entry.rule === index
                                            width: Math.min(ruleText.implicitWidth + 24, content.width)
                                            height: 28
                                            color: picked ? Style.wash : ruleHover.hovered ? Style.raised : Style.panel
                                            border.color: picked ? theme.accent : Style.line
                                            radius: Math.min(2, theme.radius)
                                            Text {
                                                id: ruleText
                                                anchors.verticalCenter: parent.verticalCenter
                                                x: 12
                                                width: parent.width - 24
                                                text: (entry.modelData.kind === "prompt"
                                                       ? (ruleChip.index === 0 ? qsTr("Always any  ") : qsTr("Always only  "))
                                                       : (ruleChip.index === 0 && entry.modelData.choices.length > 1 ? qsTr("Any  ")
                                                          : ruleChip.index === 1 ? qsTr("Only  ") : ""))
                                                      + ruleChip.modelData.join("  +  ")
                                                elide: Text.ElideRight
                                                color: ruleChip.picked ? Style.text : Style.dim
                                                font.family: Style.mono
                                                font.variableAxes: Style.narrow
                                                font.pixelSize: 11
                                            }
                                            HoverHandler { id: ruleHover; cursorShape: Qt.PointingHandCursor }
                                            TapHandler {
                                                onTapped: { panel.choose(entry.modelData, ruleChip.index); triage.forceActiveFocus() }
                                            }
                                        }
                                    }
                                }

                                // A question's options, then an answer of one's own.
                                Flow {
                                    Layout.fillWidth: true
                                    visible: entry.isSelected && entry.modelData.kind === "question"
                                             && entry.modelData.options && entry.modelData.options.length > 0
                                    spacing: 8
                                    Repeater {
                                        model: entry.isSelected && entry.modelData.kind === "question" ? entry.modelData.options : []
                                        delegate: TacticalButton {
                                            required property string modelData
                                            required property int index
                                            text: modelData
                                            key: index === 0 ? "↵" : index < 9 ? "" + (index + 1) : ""
                                            primary: index === 0
                                            onClicked: panel.answer(entry.modelData, modelData)
                                        }
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: entry.isSelected && entry.modelData.kind === "question"
                                    spacing: 10
                                    TextField {
                                        id: reply
                                        Layout.fillWidth: true
                                        placeholderText: entry.modelData.options && entry.modelData.options.length > 0
                                                         ? qsTr("Or answer in your own words") : qsTr("Your answer")
                                        font.family: Style.body
                                        font.pixelSize: 13
                                        Component.onCompleted: {
                                            const draft = panel.drafts[panel.keyOf(entry.modelData)]
                                            if (draft !== undefined) text = draft
                                        }
                                        onTextChanged: panel.drafts[panel.keyOf(entry.modelData)] = text
                                        onAccepted: panel.answer(entry.modelData, text)
                                        // Esc leaves the field rather than the inbox.
                                        Keys.onShortcutOverride: (event) => {
                                            if (event.key === Qt.Key_Escape || panel.printable(event)) event.accepted = true
                                        }
                                        Keys.onEscapePressed: triage.forceActiveFocus()
                                        Keys.onUpPressed: { triage.forceActiveFocus(); panel.select(panel.selected - 1) }
                                        Keys.onDownPressed: { triage.forceActiveFocus(); panel.select(panel.selected + 1) }
                                    }
                                    TacticalButton {
                                        text: qsTr("Send")
                                        key: "↵"
                                        visible: reply.activeFocus || reply.text.trim().length > 0
                                        enabled: reply.text.trim().length > 0
                                        onClicked: panel.answer(entry.modelData, reply.text)
                                    }
                                    TacticalButton {
                                        text: qsTr("Open")
                                        key: "O"
                                        onClicked: panel.openOperation(entry.modelData)
                                    }
                                }

                                // A permission or a refused command: the verdict.
                                CheckBox {
                                    Layout.fillWidth: true
                                    Layout.topMargin: -6
                                    Layout.bottomMargin: -6
                                    Layout.leftMargin: -8
                                    visible: entry.isSelected && entry.modelData.kind === "request"
                                    checked: panel.projectWide
                                    onToggled: { panel.projectWide = checked; triage.forceActiveFocus() }
                                    focusPolicy: Qt.NoFocus
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
                                Flow {
                                    id: verdict
                                    Layout.fillWidth: true
                                    visible: entry.isSelected && entry.modelData.kind !== "question"
                                    spacing: 10
                                    layoutDirection: Qt.RightToLeft
                                    TacticalButton {
                                        text: entry.modelData.kind === "prompt" ? qsTr("Approve once") : qsTr("Approve")
                                        key: "↵"
                                        primary: true
                                        onClicked: panel.primary(entry.modelData)
                                    }
                                    TacticalButton {
                                        visible: entry.modelData.kind === "prompt"
                                        text: qsTr("Always")
                                        key: "A"
                                        onClicked: panel.always(entry.modelData)
                                    }
                                    TacticalButton {
                                        text: qsTr("Open")
                                        key: "O"
                                        onClicked: panel.openOperation(entry.modelData)
                                    }
                                    TacticalButton {
                                        text: qsTr("Deny")
                                        key: "D"
                                        danger: true
                                        onClicked: panel.deny(entry.modelData)
                                    }
                                }
                            }
                        }
                    }
                }

                // Nothing waiting: a calm, quiet state.
                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(420, parent.width - 64)
                    visible: panel.items.length === 0
                    spacing: 10
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.bottomMargin: 6
                        implicitWidth: 8; implicitHeight: 8
                        color: Style.good
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: qsTr("Nothing waiting on you")
                        wrapMode: Text.Wrap
                        color: Style.text
                        font.family: Style.display
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                        font.letterSpacing: -0.4
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: qsTr("Questions, permissions and refused commands from every operation land here. Press I from the board to check again.")
                        wrapMode: Text.Wrap
                        color: Style.dim
                        font.family: Style.body
                        font.pixelSize: 13
                        lineHeight: 1.15
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
                spacing: 20
                TacticalButton { text: qsTr("Close"); key: "Esc"; onClicked: panel.close() }
                Flow {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    visible: panel.items.length > 0
                    spacing: 16
                    layoutDirection: Qt.RightToLeft
                    KeyHint { key: "O"; label: qsTr("Open") }
                    KeyHint { key: "D"; label: qsTr("Deny"); visible: panel.current !== null && panel.current.kind !== "question" }
                    KeyHint { key: "P"; label: qsTr("Project-wide"); visible: panel.current !== null && panel.current.kind === "request" }
                    KeyHint { key: "A"; label: qsTr("Always"); visible: panel.current !== null && panel.current.kind === "prompt" }
                    KeyHint { key: "← →"; label: qsTr("Rule"); visible: panel.current !== null && panel.current.kind !== "question"
                                                                       && panel.current.choices && panel.current.choices.length > 1 }
                    KeyHint { key: "↵"; label: panel.current && panel.current.kind === "question" ? qsTr("Send") : qsTr("Approve") }
                    KeyHint { key: "J K"; label: qsTr("Move") }
                }
                Item { Layout.fillWidth: true; visible: panel.items.length === 0 }
            }
        }
    }
}
