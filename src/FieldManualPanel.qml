import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// A project's field manual: the lessons operations learned there, to edit,
// add to, or promote into the project's CLAUDE.md.
Item {
    id: panel
    visible: false
    property string project: ""
    property var lessons: []
    property var chosen: ({})
    property string editing: ""
    property string notice: ""

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius

    function open(directory) {
        const known = ops.manuals().map(m => m.directory)
        project = directory || (known.length > 0 ? known[0] : "")
        refresh()
        notice = ""
        visible = true
        enter.restart()
    }
    function close() { visible = false }
    function refresh() {
        lessons = project.length > 0 ? ops.lessons(project) : []
        chosen = ({})
        editing = ""
        const known = ops.manuals().map(m => m.directory)
        if (project.length > 0 && known.indexOf(project) < 0)
            known.unshift(project)
        projects.model = known
        projects.currentIndex = Math.max(0, known.indexOf(project))
    }
    function promote() {
        const ids = Object.keys(chosen).filter(k => chosen[k])
        const path = ops.promoteLessons(project, ids)
        notice = path.length > 0 ? qsTr("Added to %1").arg(path) : qsTr("Nothing was added.")
        chosen = ({})
    }

    Connections {
        target: ops
        function onLessonsChanged(directory) { if (panel.visible && directory === panel.project) panel.refresh() }
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
        width: Math.min(880, parent.width - 48)
        height: Math.min(layout.implicitHeight + 2 * layout.anchors.margins, parent.height - 48)
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
            id: layout
            anchors.fill: parent
            anchors.margins: 28
            spacing: 16

            // Eyebrow, title and what the manual is.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Text {
                    Layout.fillWidth: true
                    text: "# " + qsTr("Institutional memory").toLowerCase()
                    elide: Text.ElideRight
                    color: Style.dim
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 11
                }
                Text {
                    Layout.fillWidth: true
                    text: qsTr("Field manual")
                    elide: Text.ElideRight
                    color: Style.text
                    font.family: Style.display
                    font.pixelSize: 28
                    font.weight: Font.DemiBold
                    font.letterSpacing: -0.6
                }
                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    text: qsTr("What operations learned about a project, kept by Fireteam (not in the project) and given to every new session that works there.")
                    wrapMode: Text.Wrap
                    color: Style.text2
                    font.family: Style.body
                    font.pixelSize: 13
                    lineHeight: 1.15
                }
            }

            // Which project, and whether finished operations add to it.
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                ComboBox {
                    id: projects
                    Layout.fillWidth: true
                    Material.background: Style.bg
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 12
                    onActivated: (index) => { panel.project = model[index]; panel.refresh() }
                }
                Switch {
                    checked: ops.afterAction
                    onToggled: ops.afterAction = checked
                }
                Text {
                    text: qsTr("After-action reviews")
                    color: Style.text2
                    font.family: Style.body
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    ToolTip.visible: reviewHover.hovered
                    ToolTip.text: qsTr("After each finished operation, a short read-only haiku session adds what it learned.")
                    HoverHandler { id: reviewHover }
                }
            }

            ScrollView {
                id: scroller
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: column.implicitHeight
                Layout.minimumHeight: Math.min(column.implicitHeight, 96)
                contentWidth: availableWidth
                clip: true

                ColumnLayout {
                    id: column
                    width: scroller.availableWidth
                    spacing: 0

                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.lineStrong }
                    Text {
                        visible: panel.lessons.length === 0
                        Layout.fillWidth: true
                        Layout.topMargin: 18
                        Layout.bottomMargin: 18
                        text: panel.project.length === 0 ? qsTr("No field manuals yet. They fill in as operations finish.")
                                                         : qsTr("No lessons for this project yet.")
                        wrapMode: Text.Wrap
                        color: Style.dim
                        font.family: Style.body
                        font.pixelSize: 13
                    }
                    Repeater {
                        model: panel.lessons
                        delegate: Rectangle {
                            id: lesson
                            required property var modelData
                            readonly property bool editing: panel.editing === modelData.id
                            readonly property bool picked: panel.chosen[modelData.id] === true
                            Layout.fillWidth: true
                            implicitHeight: lessonRow.implicitHeight + 16
                            color: lesson.picked ? Style.wash : lessonHover.hovered ? Style.raised : "transparent"
                            Rectangle {
                                visible: lesson.picked
                                width: 2
                                height: parent.height
                                color: theme.accent
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 1
                                color: Style.line
                            }
                            RowLayout {
                                id: lessonRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 4
                                anchors.rightMargin: 12
                                spacing: 6
                                CheckBox {
                                    Layout.alignment: Qt.AlignTop
                                    Layout.topMargin: -6
                                    checked: lesson.picked
                                    onToggled: {
                                        const next = Object.assign({}, panel.chosen)
                                        next[lesson.modelData.id] = checked
                                        panel.chosen = next
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Text {
                                        visible: !lesson.editing
                                        Layout.fillWidth: true
                                        text: lesson.modelData.text
                                        wrapMode: Text.Wrap
                                        color: Style.text
                                        font.family: Style.body
                                        font.pixelSize: 14
                                        textFormat: Text.PlainText
                                        TapHandler { onDoubleTapped: panel.editing = lesson.modelData.id }
                                    }
                                    TextField {
                                        visible: lesson.editing
                                        Layout.fillWidth: true
                                        text: lesson.modelData.text
                                        font.family: Style.body
                                        font.pixelSize: 14
                                        onAccepted: ops.editLesson(panel.project, lesson.modelData.id, text)
                                        Keys.onEscapePressed: panel.editing = ""
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: qsTr("from %1 · %2").arg(lesson.modelData.source).arg(String(lesson.modelData.added).slice(0, 10))
                                        color: Style.dim
                                        font.family: Style.mono
                                        font.variableAxes: Style.narrow
                                        font.pixelSize: 10
                                    }
                                }
                                Text {
                                    Layout.alignment: Qt.AlignTop
                                    Layout.leftMargin: 8
                                    text: "✎"
                                    color: editHover.hovered || lesson.editing ? theme.accent : Style.dim
                                    font.family: Style.mono
                                    font.pixelSize: 13
                                    HoverHandler { id: editHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: panel.editing = lesson.editing ? "" : lesson.modelData.id }
                                }
                                Text {
                                    Layout.alignment: Qt.AlignTop
                                    Layout.leftMargin: 6
                                    text: "✕"
                                    color: removeHover.hovered ? Style.danger : Style.dim
                                    font.family: Style.mono
                                    font.pixelSize: 13
                                    HoverHandler { id: removeHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: ops.removeLesson(panel.project, lesson.modelData.id) }
                                }
                            }
                            HoverHandler { id: lessonHover }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 14
                        visible: panel.project.length > 0
                        spacing: 10
                        TextField {
                            id: newLesson
                            Layout.fillWidth: true
                            placeholderText: qsTr("Add a lesson, e.g. Run the tests with DATABASE_URL=sqlite://test.db")
                            Material.background: Style.bg
                            font.family: Style.body
                            font.pixelSize: 13
                            onAccepted: if (text.trim().length > 0 && ops.addLesson(panel.project, text)) text = ""
                        }
                        TacticalButton {
                            text: qsTr("Add")
                            enabled: newLesson.text.trim().length > 0
                            onClicked: if (ops.addLesson(panel.project, newLesson.text)) newLesson.text = ""
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        visible: panel.notice.length > 0
                        spacing: 8
                        Rectangle { implicitWidth: 6; implicitHeight: 6; color: Style.good; Layout.alignment: Qt.AlignVCenter }
                        Text {
                            Layout.fillWidth: true
                            text: panel.notice
                            wrapMode: Text.Wrap
                            color: Style.text2
                            font.family: Style.mono
                            font.variableAxes: Style.narrow
                            font.pixelSize: 11
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 16
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    TacticalButton { text: qsTr("Close"); key: "Esc"; onClicked: panel.close() }
                    Item { Layout.fillWidth: true }
                    TacticalButton {
                        text: qsTr("Promote %n to CLAUDE.md", "", Object.keys(panel.chosen).filter(k => panel.chosen[k]).length)
                        enabled: Object.keys(panel.chosen).some(k => panel.chosen[k])
                        primary: enabled
                        onClicked: panel.promote()
                    }
                }
            }
        }
    }
}
