import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Totals across every operation: what the fireteams have done, how often it
// worked, what it changed, and what it would have cost at API prices.
Item {
    id: record
    visible: false
    property var stats: ({})
    readonly property var weeks: stats.weeks || []
    readonly property var projects: stats.projects || []
    // Per engine: operations, cycles run and cost, Claude Code first.
    readonly property var engines: stats.engines || []
    // Codex and Gemini CLI don't report a cost.
    function reportsCost(key) { return key === "claude" || key === "opencode" }
    readonly property real weekMax: Math.max(0.01, ...weeks.map(w => w.cost))
    readonly property int projectMax: Math.max(1, ...projects.map(p => p.runs))
    readonly property int gradeTotal: {
        const g = stats.grades || {}
        return (g["pass"] || 0) + (g["needs-work"] || 0) + (g["fail"] || 0)
    }

    function open() {
        stats = ops.serviceRecord()
        visible = true
        enter.restart()
    }
    function close() { visible = false }
    function duration(seconds) {
        const hours = Math.floor(seconds / 3600)
        const minutes = Math.floor(seconds % 3600 / 60)
        return hours > 0 ? qsTr("%1h %2m").arg(hours).arg(Style.pad(minutes)) : qsTr("%1m").arg(minutes)
    }
    function money(value) { return "$" + Number(value || 0).toLocaleString(Qt.locale(), 'f', 2) }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Style.bg.r, Style.bg.g, Style.bg.b, 0.86)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: record.close() }
    }

    Rectangle {
        id: sheet
        property real rise: 0
        anchors.centerIn: parent
        anchors.verticalCenterOffset: rise
        width: Math.min(1180, parent.width - 48)
        height: Math.min(column.implicitHeight + 64, parent.height - 48)
        color: Style.panel
        border.color: Style.lineStrong
        radius: theme.radius
        // Clicks on the panel itself mustn't reach the dismissing backdrop.
        MouseArea { anchors.fill: parent }
        Brackets { anchors.fill: parent; anchors.margins: -1; size: 12 }

        ParallelAnimation {
            id: enter
            NumberAnimation { target: sheet; property: "opacity"; from: 0; to: 1; duration: 140 }
            NumberAnimation { target: sheet; property: "rise"; from: 8; to: 0; duration: 180; easing.type: Easing.OutCubic }
        }

        ScrollView {
            anchors.fill: parent
            anchors.margins: 32
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                id: column
                width: parent.width
                spacing: 20

                ColumnLayout {
                    spacing: 4
                    Text {
                        text: "# " + qsTr("Base camp // all operations").toLowerCase()
                        color: Style.dim
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                        font.pixelSize: 11
                    }
                    Text {
                        text: qsTr("Service record")
                        color: Style.text
                        font.family: Style.display
                        font.pixelSize: 30
                        font.weight: Font.DemiBold
                        font.letterSpacing: -0.6
                    }
                }

                // The headline figures, printed wide and light on a ruled band,
                // each with a comment saying what it counts.
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.lineStrong }
                    GridLayout {
                        id: figures
                        Layout.fillWidth: true
                        columns: sheet.width > 1020 ? 6 : 3
                        columnSpacing: 0
                        rowSpacing: 0
                        Repeater {
                            model: [
                                { label: qsTr("Operations"), value: Style.pad(record.stats.operations || 0),
                                  note: qsTr("%1 deployed now").arg(record.stats.deployed || 0) },
                                { label: qsTr("Cycles run"), value: "" + (record.stats.runs || 0),
                                  note: qsTr("%1 complete · %2 failed").arg(record.stats.completed || 0).arg(record.stats.failed || 0) },
                                { label: qsTr("Success rate"), value: Math.round((record.stats.successRate || 0) * 100) + "%",
                                  note: qsTr("of cycles that finished") },
                                { label: qsTr("Lines changed"), value: "+" + (record.stats.added || 0),
                                  note: qsTr("−%1 · %n file change(s)", "", record.stats.files || 0).arg(record.stats.removed || 0) },
                                { label: qsTr("Time in the field"), value: record.duration(record.stats.seconds || 0),
                                  note: qsTr("%n hand-off(s)", "", record.stats.handoffs || 0) },
                                { label: qsTr("API value"), value: record.money(record.stats.cost),
                                  note: qsTr("API prices, not a bill") }
                            ]
                            delegate: Item {
                                required property var modelData
                                required property int index
                                readonly property bool firstInRow: index % figures.columns === 0
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.preferredWidth: 1
                                implicitHeight: cell.implicitHeight + 32
                                // Hairlines part the cells and the rows.
                                Rectangle { visible: !parent.firstInRow; width: 1; height: parent.height - 24; y: 12; color: Style.line }
                                Rectangle {
                                    visible: index >= figures.columns
                                    width: parent.width; height: 1; color: Style.line
                                }
                                ColumnLayout {
                                    id: cell
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.leftMargin: parent.firstInRow ? 0 : 18
                                    anchors.rightMargin: 12
                                    anchors.topMargin: 16
                                    spacing: 3
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.value
                                        // Long values (a German duration) shrink rather than cut.
                                        fontSizeMode: Text.HorizontalFit
                                        minimumPixelSize: 18
                                        Layout.preferredHeight: 40
                                        verticalAlignment: Text.AlignBottom
                                        color: Style.text
                                        font.family: Style.mono
                                        font.variableAxes: Style.figure
                                        font.pixelSize: 30
                                        font.letterSpacing: -0.8
                                        font.features: { "tnum": 1 }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: "# " + modelData.label
                                        elide: Text.ElideRight
                                        color: Style.text2
                                        font.family: Style.mono
                                        font.variableAxes: Style.narrow
                                        font.pixelSize: 11
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.note
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                        color: Style.dim
                                        font.family: Style.mono
                                        font.variableAxes: Style.narrow
                                        font.pixelSize: 10
                                    }
                                }
                            }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: sheet.width > 900 ? 2 : 1
                    columnSpacing: 36
                    rowSpacing: 24

                    // API value by week: one series, so the title names it and
                    // there's no legend. Hover a bar for its numbers.
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 3
                        Layout.alignment: Qt.AlignTop
                        spacing: 12
                        SectionLabel {
                            Layout.fillWidth: true
                            text: qsTr("API value by week")
                            detail: qsTr("last 8 weeks")
                        }
                        Item {
                            id: chart
                            Layout.fillWidth: true
                            implicitHeight: 210
                            readonly property real plotLeft: 0
                            readonly property real plotTop: 22
                            readonly property real plotBottom: height - 24
                            readonly property real slot: width / Math.max(1, record.weeks.length)

                            // A recessive grid: three quiet rules with their values.
                            Repeater {
                                model: 3
                                delegate: Item {
                                    required property int index
                                    readonly property real fraction: (index + 1) / 3
                                    width: chart.width
                                    y: chart.plotBottom - fraction * (chart.plotBottom - chart.plotTop)
                                    Rectangle { width: parent.width; height: 1; color: Style.line; opacity: 0.6 }
                                    Text {
                                        y: -13
                                        text: record.money(record.weekMax * parent.fraction)
                                        color: Style.faint
                                        font.family: Style.mono
                                        font.variableAxes: Style.narrow
                                        font.pixelSize: 9
                                        font.features: { "tnum": 1 }
                                    }
                                }
                            }
                            Rectangle { y: chart.plotBottom; width: parent.width; height: 1; color: Style.lineStrong }

                            Repeater {
                                model: record.weeks
                                delegate: Item {
                                    id: week
                                    required property var modelData
                                    required property int index
                                    readonly property real share: modelData.cost / record.weekMax
                                    readonly property bool current: index === record.weeks.length - 1
                                    x: index * chart.slot
                                    width: chart.slot
                                    height: chart.height

                                    // The hit target is the whole column, wider than the bar.
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.topMargin: chart.plotTop - 18
                                        anchors.bottomMargin: chart.height - chart.plotBottom
                                        color: barHover.hovered ? Style.raised : "transparent"
                                    }
                                    // A thin flat bar, its value printed over it.
                                    Rectangle {
                                        id: bar
                                        visible: week.modelData.cost > 0
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: Math.max(4, Math.min(12, chart.slot - 16))
                                        height: Math.max(2, week.share * (chart.plotBottom - chart.plotTop))
                                        y: chart.plotBottom - height
                                        color: theme.accent
                                        opacity: week.current || barHover.hovered ? 1 : 0.6
                                    }
                                    Text {
                                        visible: week.modelData.cost > 0 && chart.slot > 44
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: bar.y - 15
                                        text: record.money(week.modelData.cost)
                                        color: week.current || barHover.hovered ? Style.text : Style.dim
                                        font.family: Style.mono
                                        font.variableAxes: Style.narrow
                                        font.pixelSize: 9
                                        font.features: { "tnum": 1 }
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: chart.plotBottom + 8
                                        text: Qt.formatDate(new Date(week.modelData.start + "T00:00:00"), "d MMM")
                                        color: week.current ? Style.text : Style.dim
                                        font.family: Style.mono
                                        font.variableAxes: Style.narrow
                                        font.pixelSize: 10
                                    }
                                    HoverHandler { id: barHover }
                                    ToolTip.visible: barHover.hovered
                                    ToolTip.delay: 0
                                    ToolTip.text: qsTr("Week of %1\n%2 API value · %n cycle(s) complete", "", week.modelData.cycles)
                                                      .arg(Qt.formatDate(new Date(week.modelData.start + "T00:00:00"), "d MMMM"))
                                                      .arg(record.money(week.modelData.cost))
                                }
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: record.weeks.every(w => w.cost === 0)
                                text: qsTr("No cycles in the last eight weeks")
                                color: Style.dim
                                font.family: Style.body
                                font.pixelSize: 13
                            }
                        }

                        // Engines, when more than one has been used.
                        SectionLabel {
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            visible: record.engines.length > 1
                            text: qsTr("Engines")
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: record.engines.length > 1
                            spacing: 0
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.bottomMargin: 6
                                spacing: 12
                                Text {
                                    Layout.fillWidth: true
                                    text: qsTr("Engine")
                                    elide: Text.ElideRight
                                    color: Style.dim
                                    font.family: Style.body
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                }
                                Text {
                                    Layout.preferredWidth: 72
                                    horizontalAlignment: Text.AlignRight
                                    text: qsTr("Operations")
                                    elide: Text.ElideRight
                                    color: Style.dim
                                    font.family: Style.body
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                }
                                Text {
                                    Layout.preferredWidth: 72
                                    horizontalAlignment: Text.AlignRight
                                    text: qsTr("Cycles run")
                                    elide: Text.ElideRight
                                    color: Style.dim
                                    font.family: Style.body
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                }
                                Text {
                                    Layout.preferredWidth: 84
                                    horizontalAlignment: Text.AlignRight
                                    text: qsTr("API value")
                                    elide: Text.ElideRight
                                    color: Style.dim
                                    font.family: Style.body
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                }
                            }
                            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.lineStrong }
                            Repeater {
                                model: record.engines.length > 1 ? record.engines : []
                                delegate: Item {
                                    id: engineTotal
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Style.line }
                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 12
                                        Text {
                                            Layout.fillWidth: true
                                            text: engineTotal.modelData.label
                                            elide: Text.ElideRight
                                            color: Style.text
                                            font.family: Style.body
                                            font.pixelSize: 13
                                        }
                                        Text {
                                            Layout.preferredWidth: 72
                                            horizontalAlignment: Text.AlignRight
                                            text: engineTotal.modelData.operations
                                            color: Style.text
                                            font.family: Style.mono
                                            font.variableAxes: Style.narrow
                                            font.pixelSize: 12
                                            font.features: { "tnum": 1 }
                                        }
                                        Text {
                                            Layout.preferredWidth: 72
                                            horizontalAlignment: Text.AlignRight
                                            text: engineTotal.modelData.cycles
                                            color: Style.text
                                            font.family: Style.mono
                                            font.variableAxes: Style.narrow
                                            font.pixelSize: 12
                                            font.features: { "tnum": 1 }
                                        }
                                        Text {
                                            Layout.preferredWidth: 84
                                            horizontalAlignment: Text.AlignRight
                                            text: record.reportsCost(engineTotal.modelData.key) ? record.money(engineTotal.modelData.cost) : "—"
                                            color: Style.text2
                                            font.family: Style.mono
                                            font.variableAxes: Style.narrow
                                            font.pixelSize: 12
                                            font.features: { "tnum": 1 }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Busiest projects, by cycles run, with overwatch below.
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 2
                        Layout.alignment: Qt.AlignTop
                        spacing: 12
                        SectionLabel { Layout.fillWidth: true; text: qsTr("Busiest projects"); detail: qsTr("cycles run") }

                        // A ruled table: a firm rule under the head, hairlines between rows.
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: record.projects.length > 0
                            spacing: 0
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.bottomMargin: 6
                                spacing: 12
                                Text {
                                    Layout.fillWidth: true
                                    text: qsTr("Project")
                                    elide: Text.ElideRight
                                    color: Style.dim
                                    font.family: Style.body
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                }
                                Text {
                                    Layout.preferredWidth: 96
                                    horizontalAlignment: Text.AlignRight
                                    text: qsTr("Cycles run")
                                    elide: Text.ElideRight
                                    color: Style.dim
                                    font.family: Style.body
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                }
                                Text {
                                    Layout.preferredWidth: 84
                                    horizontalAlignment: Text.AlignRight
                                    text: qsTr("API value")
                                    elide: Text.ElideRight
                                    color: Style.dim
                                    font.family: Style.body
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                }
                            }
                            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.lineStrong }
                            Repeater {
                                model: record.projects
                                delegate: Item {
                                    id: project
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    implicitHeight: 44
                                    Rectangle {
                                        anchors.fill: parent
                                        color: projectHover.hovered ? Style.raised : "transparent"
                                    }
                                    RowLayout {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        y: 9
                                        spacing: 12
                                        Text {
                                            Layout.fillWidth: true
                                            text: project.modelData.name
                                            elide: Text.ElideMiddle
                                            color: Style.text
                                            font.family: Style.mono
                                            font.variableAxes: Style.narrow
                                            font.pixelSize: 12
                                        }
                                        Text {
                                            Layout.preferredWidth: 96
                                            horizontalAlignment: Text.AlignRight
                                            text: project.modelData.runs
                                            color: Style.text
                                            font.family: Style.mono
                                            font.variableAxes: Style.narrow
                                            font.pixelSize: 12
                                            font.features: { "tnum": 1 }
                                        }
                                        Text {
                                            Layout.preferredWidth: 84
                                            horizontalAlignment: Text.AlignRight
                                            text: record.money(project.modelData.cost)
                                            color: Style.text2
                                            font.family: Style.mono
                                            font.variableAxes: Style.narrow
                                            font.pixelSize: 12
                                            font.features: { "tnum": 1 }
                                        }
                                    }
                                    // Share of the busiest, as a thin bar under the name.
                                    Rectangle {
                                        x: 0
                                        y: 31
                                        width: parent.width - 96 - 84 - 24
                                        height: 2
                                        color: Style.line
                                        Rectangle {
                                            width: Math.max(2, parent.width * project.modelData.runs / record.projectMax)
                                            height: parent.height
                                            color: theme.accent
                                        }
                                    }
                                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Style.line }
                                    ToolTip.visible: projectHover.hovered
                                    ToolTip.delay: 300
                                    ToolTip.text: project.modelData.path
                                    HoverHandler { id: projectHover }
                                }
                            }
                        }
                        Text {
                            visible: record.projects.length === 0
                            text: qsTr("No operations yet.")
                            color: Style.dim
                            font.family: Style.body
                            font.pixelSize: 13
                        }

                        SectionLabel {
                            Layout.fillWidth: true
                            Layout.topMargin: 14
                            text: qsTr("Overwatch verdicts")
                            detail: "" + record.gradeTotal
                        }
                        // The verdicts as one split bar, then each with its
                        // square, label and count: never colour alone.
                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 4
                        Row {
                            anchors.fill: parent
                            spacing: record.gradeTotal > 0 ? 2 : 0
                            Rectangle {
                                visible: record.gradeTotal === 0
                                width: parent.width; height: 4
                                color: Style.line
                            }
                            Repeater {
                                model: record.gradeTotal > 0 ? ["pass", "needs-work", "fail"] : []
                                delegate: Rectangle {
                                    required property string modelData
                                    readonly property int count: (record.stats.grades || {})[modelData] || 0
                                    visible: count > 0
                                    width: Math.max(2, (parent.width - 4) * count / record.gradeTotal)
                                    height: 4
                                    color: Style.gradeColor(modelData)
                                }
                            }
                        }
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 22
                            Repeater {
                                model: ["pass", "needs-work", "fail"]
                                delegate: Row {
                                    required property string modelData
                                    spacing: 8
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 7; height: 7
                                        color: Style.gradeColor(modelData)
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Style.gradeLabel(modelData)
                                        color: Style.text2
                                        font.family: Style.body
                                        font.pixelSize: 13
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "" + ((record.stats.grades || {})[modelData] || 0)
                                        color: Style.text
                                        font.family: Style.mono
                                        font.variableAxes: Style.narrow
                                        font.pixelSize: 12
                                        font.features: { "tnum": 1 }
                                    }
                                }
                            }
                        }

                    }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }
                RowLayout {
                    Layout.fillWidth: true
                    TacticalButton { text: qsTr("Close"); key: "Esc"; onClicked: record.close() }
                    Item { Layout.fillWidth: true }
                }
            }
        }
    }
}
