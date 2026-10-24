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
    readonly property real weekMax: Math.max(0.01, ...weeks.map(w => w.cost))
    readonly property int projectMax: Math.max(1, ...projects.map(p => p.runs))

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
        color: Qt.rgba(0, 0, 0, 0.82)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: record.close() }
    }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(1180, parent.width - 48)
        height: Math.min(column.implicitHeight + 64, parent.height - 48)
        color: Qt.rgba(0.035, 0.043, 0.055, 0.98)
        border.color: Style.line
        radius: theme.radius
        // Clicks on the panel itself mustn't reach the dismissing backdrop.
        MouseArea { anchors.fill: parent }
        Rectangle { width: parent.width; height: 3; color: theme.accent }

        ParallelAnimation {
            id: enter
            NumberAnimation { target: sheet; property: "opacity"; from: 0; to: 1; duration: 160 }
            NumberAnimation { target: sheet; property: "scale"; from: 0.98; to: 1; duration: 220; easing.type: Easing.OutCubic }
        }

        ScrollView {
            anchors.fill: parent
            anchors.margins: 32
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                id: column
                width: parent.width
                spacing: 18

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: qsTr("Base camp // all operations")
                        color: theme.accent
                        font.family: Style.mono
                        font.pixelSize: 11
                        font.letterSpacing: 4
                        font.capitalization: Font.AllUppercase
                    }
                    Text {
                        text: qsTr("Service record")
                        color: Style.text
                        font.family: Style.display
                        font.pixelSize: 34
                        font.weight: Font.Black
                        font.letterSpacing: 5
                        font.capitalization: Font.AllUppercase
                    }
                }

                // The headline numbers, as tiles rather than a chart.
                GridLayout {
                    Layout.fillWidth: true
                    columns: Math.max(2, Math.min(6, Math.floor(sheet.width / 180)))
                    columnSpacing: 10
                    rowSpacing: 10
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
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: tile.implicitHeight + 28
                            color: Qt.rgba(1, 1, 1, 0.03)
                            border.color: Style.line
                            radius: Math.min(4, theme.radius)
                            ColumnLayout {
                                id: tile
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 14
                                spacing: 2
                                Text {
                                    text: modelData.label
                                    color: Style.dim
                                    font.family: Style.display
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    font.letterSpacing: 3
                                    font.capitalization: Font.AllUppercase
                                }
                                Text {
                                    text: modelData.value
                                    color: Style.text
                                    font.family: Style.mono
                                    font.pixelSize: 28
                                    font.bold: true
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.note
                                    elide: Text.ElideRight
                                    color: Style.faint
                                    font.family: Style.mono
                                    font.pixelSize: 10
                                }
                            }
                        }
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: sheet.width > 900 ? 2 : 1
                    columnSpacing: 28
                    rowSpacing: 18

                    // API value by week: one series, so the title names it and
                    // there's no legend. Hover a bar for its numbers.
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 3
                        Layout.alignment: Qt.AlignTop
                        spacing: 10
                        SectionLabel {
                            Layout.fillWidth: true
                            text: qsTr("API value by week")
                            detail: qsTr("last 8 weeks")
                        }
                        Item {
                            id: chart
                            Layout.fillWidth: true
                            implicitHeight: 200
                            readonly property real plotTop: 18
                            readonly property real plotBottom: height - 22
                            readonly property real slot: width / Math.max(1, record.weeks.length)

                            // A recessive grid: three quiet rules with their values.
                            Repeater {
                                model: 3
                                delegate: Item {
                                    required property int index
                                    readonly property real fraction: (index + 1) / 3
                                    width: chart.width
                                    y: chart.plotBottom - fraction * (chart.plotBottom - chart.plotTop)
                                    Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.05) }
                                    Text {
                                        y: -14
                                        text: record.money(record.weekMax * parent.fraction)
                                        color: Style.faint
                                        font.family: Style.mono
                                        font.pixelSize: 9
                                    }
                                }
                            }
                            Rectangle { y: chart.plotBottom; width: parent.width; height: 1; color: Style.line }

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
                                        anchors.bottomMargin: 22
                                        color: barHover.hovered ? Qt.rgba(1, 1, 1, 0.04) : "transparent"
                                    }
                                    Rectangle {
                                        id: bar
                                        visible: week.modelData.cost > 0
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: Math.min(28, chart.slot - 10)
                                        height: Math.max(3, week.share * (chart.plotBottom - chart.plotTop))
                                        y: chart.plotBottom - height
                                        radius: Math.min(4, width / 2)
                                        color: theme.accent
                                        opacity: week.current || barHover.hovered ? 1 : 0.7
                                        // Squares off the bottom, so only the data end is rounded.
                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            width: parent.width
                                            height: Math.min(parent.height, parent.radius)
                                            color: parent.color
                                        }
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: chart.plotBottom + 6
                                        text: Qt.formatDate(new Date(week.modelData.start + "T00:00:00"), "d MMM")
                                        color: week.current ? Style.text : Style.dim
                                        font.family: Style.mono
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
                                color: Style.faint
                                font.family: Style.display
                                font.pixelSize: 13
                            }
                        }
                    }

                    // Busiest projects, by cycles run, with overwatch below.
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 2
                        Layout.alignment: Qt.AlignTop
                        spacing: 10
                        SectionLabel { Layout.fillWidth: true; text: qsTr("Busiest projects"); detail: qsTr("cycles run") }
                        Repeater {
                            model: record.projects
                            delegate: ColumnLayout {
                                id: project
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 3
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: project.modelData.name
                                        elide: Text.ElideMiddle
                                        color: Style.text
                                        font.family: Style.mono
                                        font.pixelSize: 12
                                    }
                                    Text {
                                        text: qsTr("%1 · %2").arg(project.modelData.runs).arg(record.money(project.modelData.cost))
                                        color: Style.dim
                                        font.family: Style.mono
                                        font.pixelSize: 11
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 6
                                    color: Qt.rgba(1, 1, 1, 0.05)
                                    radius: 3
                                    Rectangle {
                                        width: Math.max(4, parent.width * project.modelData.runs / record.projectMax)
                                        height: parent.height
                                        radius: 3
                                        color: theme.accent
                                    }
                                }
                                ToolTip.visible: projectHover.hovered
                                ToolTip.delay: 300
                                ToolTip.text: project.modelData.path
                                HoverHandler { id: projectHover }
                            }
                        }
                        Text {
                            visible: record.projects.length === 0
                            text: qsTr("No operations yet.")
                            color: Style.faint
                            font.family: Style.display
                            font.pixelSize: 13
                        }

                        SectionLabel { Layout.fillWidth: true; Layout.topMargin: 10; text: qsTr("Overwatch verdicts") }
                        // Status colours, each with its label and count, never colour alone.
                        Flow {
                            Layout.fillWidth: true
                            spacing: 8
                            Repeater {
                                model: ["pass", "needs-work", "fail"]
                                delegate: Chip {
                                    required property string modelData
                                    text: Style.gradeLabel(modelData) + "  " + ((record.stats.grades || {})[modelData] || 0)
                                    tone: Style.gradeColor(modelData)
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    TacticalButton { text: qsTr("Close"); key: "Esc"; onClicked: record.close() }
                    Item { Layout.fillWidth: true }
                }
            }
        }
    }
}
