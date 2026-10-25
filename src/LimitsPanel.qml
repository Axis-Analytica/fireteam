import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Limits and timing for one operation: what it may spend before it holds, and
// when it deploys. Nothing changes until Save.
Item {
    id: panel
    visible: false
    property var op: null
    property int row: -1

    // The operation as the model has it now, so spend and status stay live
    // while the sheet is open.
    readonly property var entry: {
        const n = roster.count
        if (!op)
            return null
        for (let i = 0; i < n; ++i) {
            const item = roster.itemAt(i)
            if (item && item.opId === op.opId)
                return item
        }
        return null
    }
    readonly property var controls: entry ? (entry.controls || {}) : op && op.controls ? op.controls : ({})
    readonly property real spent: entry ? entry.cost : op ? op.cost : 0
    readonly property string status: entry ? entry.status : op ? op.status : ""
    readonly property var schedule: controls.schedule || null
    readonly property bool schedulable: status !== "deployed" && status !== "staged" && status !== "pinned"

    // The draft, applied on Save.
    property string mode: "none"
    property bool tomorrow: false
    property var others: []
    readonly property real cap: {
        const value = Number.fromLocaleString(Qt.locale(), capField.text.length > 0 ? capField.text : "0")
        return isNaN(value) ? -1 : value
    }
    readonly property int hours: hourField.text.length > 0 ? parseInt(hourField.text, 10) : -1
    readonly property int minutes: minuteField.text.length > 0 ? parseInt(minuteField.text, 10) : -1
    readonly property bool timeValid: hours >= 0 && hours <= 23 && minutes >= 0 && minutes <= 59
    // Ticks so "already passed" stays true to the clock while the sheet is open.
    property double now: Date.now()
    readonly property date deployAt: {
        const d = new Date(now)
        d.setHours(Math.max(0, hours), Math.max(0, minutes), 0, 0)
        if (tomorrow)
            d.setDate(d.getDate() + 1)
        return d
    }
    readonly property bool passed: timeValid && deployAt.getTime() <= now
    readonly property string afterId: afterBox.currentIndex >= 0 && afterBox.currentIndex < others.length
                                      ? others[afterBox.currentIndex].opId : ""
    readonly property bool valid: cap >= 0
                                  && (!schedulable || mode === "none" || mode === "reset"
                                      || (mode === "time" && timeValid && !passed)
                                      || (mode === "after" && afterId.length > 0))

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius
    Material.background: Style.panel

    function open(target, targetRow) {
        op = target
        row = targetRow
        now = Date.now()
        const c = controls
        const usd = Number(c.budgetUsd || 0)
        capField.text = usd > 0 ? Number(usd).toLocaleString(Qt.locale(), 'f', 2).replace(Qt.locale().groupSeparator, "") : ""
        planSlider.value = Number(c.budgetPlan || 0)

        // Every other operation it could wait for, finished ones aside.
        const list = []
        for (let i = 0; i < roster.count; ++i) {
            const item = roster.itemAt(i)
            if (item && item.opId !== target.opId && item.status !== "complete" && !item.archived)
                list.push({ opId: item.opId, codename: item.codename, status: item.status,
                            label: item.codename + "  ·  " + Style.statusLabel(item.status) })
        }
        others = list

        const s = c.schedule
        mode = s && s.mode ? s.mode : "none"
        if (s && s.mode === "time" && s.at > 0) {
            const at = new Date(s.at * 1000)
            hourField.text = Style.pad(at.getHours())
            minuteField.text = Style.pad(at.getMinutes())
            const today = new Date(now)
            tomorrow = at.getDate() !== today.getDate()
        } else {
            // A sensible default: the top of the next hour.
            const next = new Date(now + 3600 * 1000)
            hourField.text = Style.pad(next.getHours())
            minuteField.text = "00"
            pickDay()
        }
        afterBox.currentIndex = s && s.mode === "after" ? list.findIndex(o => o.opId === s.after) : (list.length > 0 ? 0 : -1)

        visible = true
        enter.restart()
        scroller.ScrollBar.vertical.position = 0
        capField.forceActiveFocus()
    }
    function close() { visible = false }

    // Tomorrow when today's time has already gone.
    function pickDay() {
        if (!timeValid)
            return
        const d = new Date(now)
        d.setHours(hours, minutes, 0, 0)
        tomorrow = d.getTime() <= now
    }
    function money(value) { return "$" + Number(value).toLocaleString(Qt.locale(), 'f', 2) }

    function save() {
        if (!valid)
            return
        const usd = Math.round(cap * 100) / 100
        const plan = Math.round(planSlider.value)
        if (usd !== Number(controls.budgetUsd || 0) || plan !== Number(controls.budgetPlan || 0))
            ops.setBudget(row, usd, plan)
        if (schedulable) {
            if (mode === "none") {
                if (schedule)
                    ops.clearSchedule(row)
            } else {
                const at = mode === "time" ? Math.floor(deployAt.getTime() / 1000) : 0
                const after = mode === "after" ? afterId : ""
                const same = schedule && schedule.mode === mode
                             && (mode !== "time" || Number(schedule.at) === at)
                             && (mode !== "after" || schedule.after === after)
                if (!same)
                    ops.setSchedule(row, mode, at, after)
            }
        }
        close()
    }

    // Every operation's id, name, status, spend and limits, read live.
    Repeater {
        id: roster
        model: ops
        delegate: Item {
            required property string opId
            required property string codename
            required property string status
            required property double cost
            required property var controls
            required property bool archived
        }
    }

    Timer { interval: 20000; repeat: true; running: panel.visible; onTriggered: panel.now = Date.now() }

    // A setting: its name and what it does on the left, its control on the right.
    component OptionRow: RowLayout {
        id: optionRow
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
                text: optionRow.label
                wrapMode: Text.Wrap
                color: Style.text
                font.family: Style.body
                font.pixelSize: 14
                font.weight: Font.Medium
            }
            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: optionRow.hint
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

    // A row of choices, one picked: the picked one washed with an accent rule beneath.
    component Segmented: Rectangle {
        id: seg
        property var options: []
        property string current
        property bool stretch: false
        signal picked(string key)
        implicitWidth: segRow.implicitWidth + 2
        implicitHeight: 34
        color: Style.bg
        border.color: Style.line
        radius: Math.min(2, theme.radius)
        opacity: enabled ? 1 : 0.4
        RowLayout {
            id: segRow
            anchors.fill: parent
            anchors.margins: 1
            spacing: 0
            Repeater {
                model: seg.options
                delegate: Rectangle {
                    id: choice
                    required property var modelData
                    required property int index
                    readonly property bool chosen: seg.current === modelData.key
                    Layout.fillWidth: seg.stretch
                    Layout.fillHeight: true
                    Layout.preferredWidth: seg.stretch ? choiceLabel.implicitWidth + 24 : -1
                    implicitWidth: choiceLabel.implicitWidth + 24
                    color: chosen ? Style.wash : choiceHover.hovered && seg.enabled ? Style.raised : "transparent"
                    Rectangle {
                        visible: choice.index > 0
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 1
                        color: Style.line
                    }
                    Text {
                        id: choiceLabel
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - 16)
                        elide: Text.ElideRight
                        text: choice.modelData.label
                        color: choice.chosen ? Style.text : choiceHover.hovered && seg.enabled ? Style.text2 : Style.dim
                        font.family: Style.body
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    Rectangle {
                        visible: choice.chosen
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 2
                        color: theme.accent
                    }
                    HoverHandler { id: choiceHover; enabled: seg.enabled; cursorShape: Qt.PointingHandCursor }
                    TapHandler { enabled: seg.enabled; onTapped: seg.picked(choice.modelData.key) }
                }
            }
        }
    }

    // A small typed number: mono, centred, no floating label.
    // A well for typed values: square, ground-coloured, accent edge when focused.
    component Well: Rectangle {
        property bool focused: false
        color: Style.bg
        border.color: focused ? theme.accent : Style.line
        radius: Math.min(2, theme.radius)
    }
    component NumberField: TextField {
        id: numberField
        background: Well { focused: numberField.activeFocus }
        color: Style.text
        implicitWidth: 52
        implicitHeight: 34
        topPadding: 4
        bottomPadding: 4
        leftPadding: 8
        rightPadding: 8
        horizontalAlignment: TextInput.AlignHCenter
        maximumLength: 2
        inputMethodHints: Qt.ImhDigitsOnly
        validator: IntValidator { bottom: 0; top: 59 }
        font.family: Style.mono
        font.variableAxes: Style.narrow
        font.pixelSize: 14
        font.features: { "tnum": 1 }
        selectByMouse: true
        onActiveFocusChanged: if (activeFocus) selectAll()
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
        width: Math.min(680, parent.width - 48)
        height: Math.min(column.implicitHeight, parent.height - 48)
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
            id: column
            anchors.fill: parent
            spacing: 0

            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: 32
                Layout.topMargin: 28
                Layout.bottomMargin: 20
                spacing: 4
                Text {
                    Layout.fillWidth: true
                    text: panel.op ? "# " + qsTr("Limits").toLowerCase() + " // " + panel.op.codename : ""
                    elide: Text.ElideRight
                    color: Style.dim
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 11
                }
                Text {
                    Layout.fillWidth: true
                    text: qsTr("Budget and schedule")
                    elide: Text.ElideRight
                    color: Style.text
                    font.family: Style.display
                    font.pixelSize: 28
                    font.weight: Font.DemiBold
                    font.letterSpacing: -0.6
                }
            }

            Rule {}

            ScrollView {
                id: scroller
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: content.implicitHeight + 40
                contentWidth: availableWidth
                clip: true

                ColumnLayout {
                    id: content
                    x: 32
                    y: 20
                    width: scroller.availableWidth - 64
                    spacing: 14

                    // ── Budget ───────────────────────────────────────────
                    SectionLabel { Layout.fillWidth: true; text: qsTr("Budget") }

                    OptionRow {
                        label: qsTr("API value cap")
                        hint: panel.cap > 0 && panel.spent >= panel.cap
                              ? qsTr("≈%1 spent, already past this cap: it holds after its current cycle.").arg(panel.money(panel.spent))
                              : panel.cap > 0
                              ? qsTr("≈%1 spent of %2").arg(panel.money(panel.spent)).arg(panel.money(panel.cap))
                              : qsTr("≈%1 spent so far. Empty or 0 is no cap.").arg(panel.money(panel.spent))
                        TextField {
                                id: capField
                                implicitWidth: 132
                                implicitHeight: 34
                                topPadding: 4
                                bottomPadding: 4
                                leftPadding: 28
                                rightPadding: 10
                                horizontalAlignment: TextInput.AlignRight
                                color: Style.text
                                background: Well {
                                    focused: capField.activeFocus
                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "$"
                                        color: Style.dim
                                        font.family: Style.mono
                                        font.variableAxes: Style.narrow
                                        font.pixelSize: 14
                                    }
                                    Text {
                                        visible: capField.text.length === 0
                                        anchors.right: parent.right
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: qsTr("No cap")
                                        color: Style.faint
                                        font.family: Style.body
                                        font.pixelSize: 13
                                    }
                                }
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                validator: DoubleValidator { bottom: 0; top: 100000; decimals: 2; notation: DoubleValidator.StandardNotation }
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 14
                                font.features: { "tnum": 1 }
                                selectByMouse: true
                                onActiveFocusChanged: if (activeFocus) selectAll()
                                onAccepted: panel.save()
                        }
                    }
                    // Spend against the cap: amber from the 80% warning, red at the cap.
                    Item {
                        Layout.fillWidth: true
                        Layout.topMargin: -6
                        visible: panel.cap > 0
                        implicitHeight: 3
                        readonly property real share: panel.cap > 0 ? Math.min(1, panel.spent / panel.cap) : 0
                        Rectangle { anchors.fill: parent; color: Style.line }
                        Rectangle {
                            width: parent.width * parent.share
                            height: parent.height
                            color: parent.share >= 1 ? Style.danger : parent.share >= 0.8 ? Style.amber : theme.accent
                        }
                        Rectangle {
                            // The 80% warning mark.
                            x: parent.width * 0.8
                            y: -2
                            width: 1
                            height: parent.height + 4
                            color: Style.dim
                        }
                    }

                    Rule {}

                    OptionRow {
                        label: qsTr("Share of the plan's 5-hour window")
                        hint: {
                            const w = ops.usage.windows && ops.usage.windows.five_hour
                            return w !== undefined && w !== null
                                    ? qsTr("Holds once the window passes this much use. It's %1% used now.").arg(Math.round(w.utilization * 100))
                                    : qsTr("Holds once the window passes this much use.")
                        }
                        RowLayout {
                            spacing: 10
                            Slider {
                                id: planSlider
                                implicitWidth: 168
                                from: 0
                                to: 100
                                // Steps of 5 without the tick marks a snapping slider draws.
                                onMoved: value = Math.round(value / 5) * 5
                            }
                            Text {
                                Layout.preferredWidth: 52
                                horizontalAlignment: Text.AlignRight
                                text: planSlider.value > 0 ? Math.round(planSlider.value) + "%" : qsTr("Off")
                                color: planSlider.value > 0 ? Style.text : Style.dim
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 14
                                font.features: { "tnum": 1 }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: qsTr("At a limit the operation finishes its current cycle, then holds until you raise the limit. At 80% of the cap it warns you once.")
                        wrapMode: Text.Wrap
                        color: Style.text2
                        font.family: Style.body
                        font.pixelSize: 13
                        lineHeight: 1.15
                    }

                    // ── Schedule ─────────────────────────────────────────
                    SectionLabel {
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        text: qsTr("Schedule")
                        detail: panel.schedule && panel.status === "scheduled" ? qsTr("set") : ""
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: !panel.schedulable
                        text: panel.status === "deployed" ? qsTr("It's deployed now. Scheduling is for an operation that isn't running or queued.")
                            : panel.status === "staged" ? qsTr("It's queued for the next free slot. Scheduling is for an operation that isn't running or queued.")
                            : qsTr("It's pinned down by the plan's usage limit and resumes on its own when the limit resets.")
                        wrapMode: Text.Wrap
                        color: Style.amber
                        font.family: Style.body
                        font.pixelSize: 13
                        lineHeight: 1.15
                    }

                    Segmented {
                        id: modePicker
                        Layout.fillWidth: true
                        stretch: true
                        enabled: panel.schedulable
                        current: panel.mode
                        options: [
                            { key: "none", label: qsTr("None") },
                            { key: "time", label: qsTr("At a time") },
                            { key: "reset", label: qsTr("When usage resets") },
                            { key: "after", label: qsTr("After another operation") }
                        ]
                        onPicked: (key) => panel.mode = key
                    }

                    // At a time.
                    RowLayout {
                        Layout.fillWidth: true
                        visible: panel.mode === "time"
                        enabled: panel.schedulable
                        opacity: enabled ? 1 : 0.4
                        spacing: 8
                        NumberField {
                            id: hourField
                            validator: IntValidator { bottom: 0; top: 23 }
                                                        onTextEdited: panel.pickDay()
                            onEditingFinished: if (text.length === 1) text = "0" + text
                        }
                        Text {
                            text: ":"
                            color: Style.dim
                            font.family: Style.mono
                            font.variableAxes: Style.narrow
                            font.pixelSize: 14
                        }
                        NumberField {
                            id: minuteField
                                                        onTextEdited: panel.pickDay()
                            onEditingFinished: if (text.length === 1) text = "0" + text
                        }
                        Segmented {
                            Layout.leftMargin: 8
                            current: panel.tomorrow ? "tomorrow" : "today"
                            options: [{ key: "today", label: qsTr("Today") }, { key: "tomorrow", label: qsTr("Tomorrow") }]
                            onPicked: (key) => panel.tomorrow = key === "tomorrow"
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: !panel.timeValid ? qsTr("Enter a 24-hour time")
                                : panel.passed ? qsTr("That time has passed")
                                : qsTr("Deploys %1").arg(Qt.locale().toString(panel.deployAt, "ddd HH:mm"))
                            color: !panel.timeValid || panel.passed ? Style.amber : Style.text
                            font.family: Style.mono
                            font.variableAxes: Style.narrow
                            font.pixelSize: 13
                        }
                    }

                    // When usage resets.
                    Text {
                        Layout.fillWidth: true
                        visible: panel.mode === "reset"
                        text: {
                            const at = Number(ops.usage.resetsAt || 0)
                            return at * 1000 > panel.now
                                    ? qsTr("Deploys when the plan's usage window resets, at %1.").arg(Qt.locale().toString(new Date(at * 1000), "ddd HH:mm"))
                                    : qsTr("Deploys when the plan's usage window resets, or at once if the plan isn't limited now.")
                        }
                        wrapMode: Text.Wrap
                        color: Style.text2
                        font.family: Style.body
                        font.pixelSize: 13
                        lineHeight: 1.15
                        opacity: panel.schedulable ? 1 : 0.4
                    }

                    // After another operation.
                    OptionRow {
                        visible: panel.mode === "after"
                        enabled: panel.schedulable
                        label: qsTr("Deploys when this completes")
                        hint: panel.others.length === 0 ? qsTr("There's no other unfinished operation to wait for.") : ""
                        ComboBox {
                            id: afterBox
                            implicitWidth: 260
                            implicitHeight: 40
                            topInset: 0
                            bottomInset: 0
                            enabled: panel.others.length > 0
                            model: panel.others
                            textRole: "label"
                            displayText: currentIndex >= 0 ? currentText : qsTr("No operation")
                            font.family: Style.mono
                            font.variableAxes: Style.narrow
                            font.pixelSize: 12
                            Material.background: Style.bg
                        }
                    }
                }
            }

            Rule {}

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 32
                Layout.rightMargin: 32
                Layout.topMargin: 16
                Layout.bottomMargin: 16
                spacing: 10
                TacticalButton { text: qsTr("Cancel"); key: "Esc"; onClicked: panel.close() }
                Item { Layout.fillWidth: true }
                TacticalButton {
                    visible: panel.schedule !== null && panel.schedulable
                    text: qsTr("Clear schedule")
                    onClicked: { ops.clearSchedule(panel.row); panel.close() }
                }
                TacticalButton {
                    text: qsTr("Save")
                    key: "Ctrl+Enter"
                    primary: true
                    enabled: panel.valid
                    onClicked: panel.save()
                }
            }
        }
    }

    Shortcut {
        enabled: panel.visible
        sequences: ["Ctrl+Return", "Ctrl+Enter"]
        context: Qt.ApplicationShortcut
        onActivated: panel.save()
    }
}
