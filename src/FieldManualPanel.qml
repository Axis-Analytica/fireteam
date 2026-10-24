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
        color: Qt.rgba(0, 0, 0, 0.8)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: panel.close() }
    }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(880, parent.width - 48)
        height: Math.min(column.implicitHeight + 64, parent.height - 48)
        color: Qt.rgba(0.04, 0.05, 0.065, 0.97)
        border.color: Style.line
        radius: theme.radius
        // Clicks on the panel itself mustn't reach the dismissing backdrop.
        MouseArea { anchors.fill: parent }
        Rectangle { width: parent.width; height: 3; color: theme.accent }

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
                spacing: 12

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: qsTr("Institutional memory")
                        color: theme.accent
                        font.family: Style.mono
                        font.pixelSize: 11
                        font.letterSpacing: 4 * Style.tracking
                        font.capitalization: Font.AllUppercase
                    }
                    Text {
                        text: qsTr("Field manual")
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
                        text: qsTr("What operations learned about a project, kept by Fireteam (not in the project) and given to every new session that works there.")
                        wrapMode: Text.Wrap
                        color: Style.dim
                        font.family: Style.display
                        font.pixelSize: 13
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    ComboBox {
                        id: projects
                        Layout.fillWidth: true
                        font.family: Style.mono
                        font.pixelSize: 12
                        onActivated: (index) => { panel.project = model[index]; panel.refresh() }
                    }
                    Switch {
                        checked: ops.afterAction
                        onToggled: ops.afterAction = checked
                    }
                    Text {
                        text: qsTr("After-action reviews")
                        color: Style.dim
                        font.family: Style.display
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.letterSpacing: 2 * Style.tracking
                        font.capitalization: Font.AllUppercase
                        ToolTip.visible: reviewHover.hovered
                        ToolTip.text: qsTr("After each finished operation, a short read-only haiku session adds what it learned.")
                        HoverHandler { id: reviewHover }
                    }
                }

                Text {
                    visible: panel.lessons.length === 0
                    Layout.fillWidth: true
                    text: panel.project.length === 0 ? qsTr("No field manuals yet. They fill in as operations finish.")
                                                     : qsTr("No lessons for this project yet.")
                    wrapMode: Text.Wrap
                    color: Style.faint
                    font.family: Style.display
                    font.pixelSize: 13
                }
                Repeater {
                    model: panel.lessons
                    delegate: Rectangle {
                        id: lesson
                        required property var modelData
                        readonly property bool editing: panel.editing === modelData.id
                        Layout.fillWidth: true
                        implicitHeight: lessonRow.implicitHeight + 16
                        color: lessonHover.hovered ? Qt.rgba(1, 1, 1, 0.04) : "transparent"
                        border.color: Style.line
                        radius: Math.min(4, theme.radius)
                        RowLayout {
                            id: lessonRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 6
                            anchors.rightMargin: 10
                            spacing: 8
                            CheckBox {
                                checked: panel.chosen[lesson.modelData.id] === true
                                onToggled: {
                                    const next = Object.assign({}, panel.chosen)
                                    next[lesson.modelData.id] = checked
                                    panel.chosen = next
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Text {
                                    visible: !lesson.editing
                                    Layout.fillWidth: true
                                    text: lesson.modelData.text
                                    wrapMode: Text.Wrap
                                    color: Style.text
                                    font.family: Style.display
                                    font.pixelSize: 13
                                    textFormat: Text.PlainText
                                    TapHandler { onDoubleTapped: panel.editing = lesson.modelData.id }
                                }
                                TextField {
                                    visible: lesson.editing
                                    Layout.fillWidth: true
                                    text: lesson.modelData.text
                                    font.family: Style.display
                                    font.pixelSize: 13
                                    onAccepted: ops.editLesson(panel.project, lesson.modelData.id, text)
                                    Keys.onEscapePressed: panel.editing = ""
                                }
                                Text {
                                    text: qsTr("from %1 · %2").arg(lesson.modelData.source).arg(String(lesson.modelData.added).slice(0, 10))
                                    color: Style.faint
                                    font.family: Style.mono
                                    font.pixelSize: 10
                                }
                            }
                            Text {
                                text: "✎"
                                color: editHover.hovered ? theme.accent : Style.dim
                                font.pixelSize: 13
                                HoverHandler { id: editHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: panel.editing = lesson.editing ? "" : lesson.modelData.id }
                            }
                            Text {
                                text: "✕"
                                color: removeHover.hovered ? Style.danger : Style.dim
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
                    visible: panel.project.length > 0
                    spacing: 10
                    TextField {
                        id: newLesson
                        Layout.fillWidth: true
                        placeholderText: qsTr("Add a lesson, e.g. Run the tests with DATABASE_URL=sqlite://test.db")
                        font.family: Style.display
                        font.pixelSize: 13
                        onAccepted: if (text.trim().length > 0 && ops.addLesson(panel.project, text)) text = ""
                    }
                    TacticalButton {
                        text: qsTr("Add")
                        enabled: newLesson.text.trim().length > 0
                        onClicked: if (ops.addLesson(panel.project, newLesson.text)) newLesson.text = ""
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: panel.notice.length > 0
                    text: panel.notice
                    wrapMode: Text.Wrap
                    color: Style.good
                    font.family: Style.mono
                    font.pixelSize: 12
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    TacticalButton { text: qsTr("Close"); key: "Esc"; onClicked: panel.close() }
                    Item { Layout.fillWidth: true }
                    TacticalButton {
                        text: qsTr("Promote %n to CLAUDE.md", "", Object.keys(panel.chosen).filter(k => panel.chosen[k]).length)
                        enabled: Object.keys(panel.chosen).some(k => panel.chosen[k])
                        onClicked: panel.promote()
                    }
                }
            }
        }
    }
}
