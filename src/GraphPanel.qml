import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// A project's knowledge graph, as a survey of its files: each file a square
// sized by what it holds, lines where files lean on each other, dashed rings
// around the communities they form, and the files operations changed lit in
// the accent. Built by graphify from the code alone.
Item {
    id: panel
    visible: false
    property string project: ""
    property var graph: ({})
    property var projects: []
    // Whose work is lit: "" for every operation, or one operation's id.
    property string workBy: ""
    property int selected: -1
    property int hovered: -1
    property var detail: ({})

    // theme.accent is a name ("#ffd60a"); as a colour its channels can be read.
    readonly property color accent: theme.accent
    readonly property var files: graph.files || []
    readonly property var links: graph.links || []
    readonly property var activity: graph.activity || ({})
    readonly property string state: graph.state || "none"
    // Every operation that touched this project, for the work filter.
    readonly property var workers: {
        const seen = {}, list = []
        for (const path in activity)
            for (const entry of activity[path])
                if (!seen[entry.opId]) { seen[entry.opId] = true; list.push(entry) }
        return list.sort((a, b) => a.codename.localeCompare(b.codename))
    }
    // How many cycles of the chosen work touched a file.
    function heat(path) {
        const entries = activity[path] || []
        let total = 0
        for (const entry of entries)
            if (workBy === "" || entry.opId === workBy)
                total += entry.cycles
        return total
    }
    readonly property int hottest: {
        let most = 0
        for (const file of files)
            most = Math.max(most, heat(file.path))
        return most
    }
    // Files linked to the one in focus.
    readonly property int focusIndex: hovered >= 0 ? hovered : selected
    readonly property var neighbours: {
        const set = {}
        if (focusIndex < 0) return set
        for (const link of links) {
            if (link.a === focusIndex) set[link.b] = true
            else if (link.b === focusIndex) set[link.a] = true
        }
        return set
    }

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius
    Material.background: Style.panel

    function open(directory, opId) {
        projects = ops.graphProjects()
        const chosen = directory || project || (projects.length > 0 ? projects[0].directory : "")
        workBy = opId || ""
        load(chosen)
        visible = true
        enter.restart()
        stage.fit()
    }
    function close() { visible = false }
    function load(directory) {
        if (directory !== project) {
            selected = -1
            hovered = -1
            detail = ({})
        }
        project = directory
        graph = directory.length > 0 ? ops.graph(directory) : ({})
        if (selected >= files.length)
            selected = -1
        edges.requestPaint()
    }
    function select(index) {
        selected = index
        detail = index >= 0 ? ops.graphFileDetail(project, files[index].path) : ({})
        edges.requestPaint()
    }
    function indexOf(path) {
        for (let i = 0; i < files.length; ++i)
            if (files[i].path === path) return i
        return -1
    }
    function baseName(path) { return path.slice(path.lastIndexOf("/") + 1) }
    function css(c, alpha) { return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + alpha + ")" }

    Connections {
        target: ops
        function onGraphChanged(directory) {
            panel.projects = ops.graphProjects()
            if (panel.visible && directory === panel.project)
                panel.load(directory)
        }
    }
    onFocusIndexChanged: edges.requestPaint()
    onWorkByChanged: edges.requestPaint()

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Style.bg.r, Style.bg.g, Style.bg.b, 0.9)
        MouseArea { anchors.fill: parent; onClicked: panel.close() }
    }

    Rectangle {
        id: sheet
        anchors.fill: parent
        anchors.margins: 24
        color: Style.panel
        border.color: Style.lineStrong
        radius: theme.radius
        MouseArea { anchors.fill: parent }
        Brackets { anchors.fill: parent; anchors.margins: -1; size: 12 }

        ParallelAnimation {
            id: enter
            NumberAnimation { target: sheet; property: "opacity"; from: 0; to: 1; duration: 140 }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 24

            // Projects, the graph's figures, hubs, and whose work is lit.
            ColumnLayout {
                Layout.preferredWidth: sheet.width < 1000 ? 230 : 280
                Layout.maximumWidth: Layout.preferredWidth
                Layout.fillHeight: true
                spacing: 12

                ColumnLayout {
                    spacing: 4
                    Text {
                        text: "# " + qsTr("Recon").toLowerCase() + " // graphify"
                        color: Style.dim
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                        font.pixelSize: 11
                    }
                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Knowledge graph")
                        elide: Text.ElideRight
                        color: Style.text
                        font.family: Style.display
                        font.pixelSize: 28
                        font.weight: Font.DemiBold
                        font.letterSpacing: -0.6
                    }
                }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }

                ListView {
                    id: projectList
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, 200)
                    clip: true
                    model: panel.projects
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        id: projectRow
                        required property var modelData
                        readonly property bool chosen: modelData.directory === panel.project
                        width: ListView.view.width
                        height: 46
                        color: chosen ? Style.wash : projectHover.hovered ? Style.raised : "transparent"
                        Rectangle { visible: projectRow.chosen; width: 2; height: parent.height; color: theme.accent }
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 8
                            anchors.topMargin: 6
                            anchors.bottomMargin: 6
                            spacing: 1
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Rectangle {
                                    implicitWidth: 6; implicitHeight: 6
                                    color: projectRow.modelData.state === "ready" ? theme.accent
                                         : projectRow.modelData.state === "failed" ? Style.danger
                                         : projectRow.modelData.state === "building" ? Style.amber : Style.faint
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: panel.baseName(projectRow.modelData.directory)
                                    elide: Text.ElideRight
                                    color: projectRow.chosen ? Style.text : Style.text2
                                    font.family: Style.mono
                                    font.variableAxes: Style.wide
                                    font.pixelSize: 13
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: projectRow.modelData.directory
                                elide: Text.ElideMiddle
                                color: Style.dim
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 10
                            }
                        }
                        HoverHandler { id: projectHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { panel.load(projectRow.modelData.directory); stage.fit() } }
                    }
                }
                Text {
                    visible: panel.projects.length === 0
                    Layout.fillWidth: true
                    text: qsTr("Projects appear here once an operation has worked in them.")
                    wrapMode: Text.Wrap
                    color: Style.faint
                    font.family: Style.body
                    font.pixelSize: 12
                }

                // The figures, ruled like a tool's output.
                GridLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    visible: panel.state === "ready" || (panel.files.length > 0)
                    columns: 2
                    rowSpacing: 10
                    columnSpacing: 10
                    Figure { Layout.fillWidth: true; alignment: Qt.AlignLeft; size: 22; value: "" + (panel.graph.stats ? panel.graph.stats.files : 0); comment: qsTr("Files").toLowerCase() }
                    Figure { Layout.fillWidth: true; alignment: Qt.AlignLeft; size: 22; value: "" + (panel.graph.stats ? panel.graph.stats.symbols : 0); comment: qsTr("Symbols").toLowerCase() }
                    Figure { Layout.fillWidth: true; alignment: Qt.AlignLeft; size: 22; value: "" + (panel.graph.stats ? panel.graph.stats.links : 0); comment: qsTr("Links").toLowerCase() }
                    Figure { Layout.fillWidth: true; alignment: Qt.AlignLeft; size: 22; value: "" + (panel.graph.stats ? panel.graph.stats.communities : 0); comment: qsTr("Communities").toLowerCase() }
                }

                SectionLabel { Layout.fillWidth: true; Layout.topMargin: 6; visible: (panel.graph.hubs || []).length > 0; text: qsTr("Hubs") }
                Repeater {
                    model: (panel.graph.hubs || []).slice(0, sheet.height > 760 ? 6 : 4)
                    delegate: RowLayout {
                        id: hub
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: hub.modelData.label
                            elide: Text.ElideRight
                            color: hubHover.hovered ? theme.accent : Style.text2
                            font.family: Style.mono
                            font.variableAxes: Style.narrow
                            font.pixelSize: 12
                            HoverHandler { id: hubHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: panel.select(panel.indexOf(hub.modelData.path)) }
                        }
                        Text {
                            text: hub.modelData.degree
                            color: Style.dim
                            font.family: Style.mono
                            font.variableAxes: Style.narrow
                            font.pixelSize: 11
                        }
                    }
                }

                SectionLabel { Layout.fillWidth: true; Layout.topMargin: 6; visible: panel.workers.length > 0; text: qsTr("Work shown") }
                ComboBox {
                    Layout.fillWidth: true
                    visible: panel.workers.length > 0
                    font.family: Style.body
                    Material.background: Style.bg
                    model: [qsTr("Every operation")].concat(panel.workers.map(w => w.codename))
                    currentIndex: panel.workBy === "" ? 0 : 1 + panel.workers.findIndex(w => w.opId === panel.workBy)
                    onActivated: (index) => panel.workBy = index === 0 ? "" : panel.workers[index - 1].opId
                }

                Item { Layout.fillHeight: true }
                Text {
                    Layout.fillWidth: true
                    visible: panel.graph.builtAt !== undefined
                    text: "# " + qsTr("Built %1").arg(Qt.formatDateTime(new Date(panel.graph.builtAt), "d MMM HH:mm")).toLowerCase()
                          + (panel.graph.commit ? " · " + String(panel.graph.commit).slice(0, 7) : "")
                    elide: Text.ElideRight
                    color: Style.dim
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 10
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    TacticalButton { text: qsTr("Close"); key: "Esc"; onClicked: panel.close() }
                    Item { Layout.fillWidth: true }
                    TacticalButton {
                        visible: ops.graphify.length > 0 && panel.project.length > 0
                        enabled: panel.state !== "building"
                        text: panel.state === "none" ? qsTr("Map") : qsTr("Rebuild")
                        primary: panel.state === "none"
                        onClicked: ops.buildGraph(panel.project)
                    }
                }
            }

            // The map.
            Rectangle {
                id: frame
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Style.bg
                border.color: Style.line
                radius: theme.radius
                clip: true
                // Unzoomed, the map stays centred as the drawer comes and goes.
                onWidthChanged: if (stage.scale === 1) stage.fit()
                onHeightChanged: if (stage.scale === 1) stage.fit()

                // A survey sheet's ticks, fixed while the map moves.
                Canvas {
                    anchors.fill: parent
                    property color ink: Style.text
                    onInkChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        ctx.fillStyle = panel.css(ink, 0.07)
                        for (let x = 48; x < width; x += 48)
                            for (let y = 48; y < height; y += 48) {
                                ctx.fillRect(x - 2, y, 5, 1)
                                ctx.fillRect(x, y - 2, 1, 5)
                            }
                    }
                }

                Item {
                    id: stage
                    // The graph's own field, in which positions are 0..1: as tall as
                    // the frame, and wider on a wide screen (up to twice as wide),
                    // so a cluster spreads into the room rather than sitting in a
                    // square in the middle.
                    height: Math.max(200, frame.height - 80)
                    width: Math.max(200, Math.min(frame.width - 120, height * 2))
                    transformOrigin: Item.TopLeft
                    function fit() {
                        scale = 1
                        x = (frame.width - width) / 2
                        y = (frame.height - height) / 2
                    }
                    function zoom(factor, px, py) {
                        const next = Math.max(0.4, Math.min(5, scale * factor))
                        // Keep the point under the pointer still.
                        x = px - (px - x) * next / scale
                        y = py - (py - y) * next / scale
                        scale = next
                    }
                    Component.onCompleted: fit()

                    // Community rings and the links, drawn together.
                    Canvas {
                        id: edges
                        anchors.fill: parent
                        property color ink: Style.text
                        property color accent: theme.accent
                        onInkChanged: requestPaint()
                        onAccentChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset()
                            const files = panel.files, w = width, h = height
                            // A dashed ring around each community of three files or more.
                            const groups = {}
                            files.forEach(f => (groups[f.community] = groups[f.community] || []).push(f))
                            ctx.setLineDash([3, 5])
                            ctx.lineWidth = 1 / stage.scale
                            for (const id in groups) {
                                const members = groups[id]
                                if (members.length < 3) continue
                                const cx = members.reduce((s, f) => s + f.x, 0) / members.length
                                const cy = members.reduce((s, f) => s + f.y, 0) / members.length
                                const r = Math.max(...members.map(f => Math.hypot(f.x - cx, f.y - cy))) + 0.035
                                ctx.strokeStyle = panel.css(ink, 0.13)
                                ctx.beginPath()
                                ctx.ellipse((cx - r) * w, (cy - r) * h, 2 * r * w, 2 * r * h)
                                ctx.stroke()
                            }
                            ctx.setLineDash([])
                            const focus = panel.focusIndex
                            for (const link of panel.links) {
                                const a = files[link.a], b = files[link.b]
                                if (!a || !b) continue
                                const lit = focus >= 0 && (link.a === focus || link.b === focus)
                                ctx.strokeStyle = lit ? panel.css(accent, 0.85) : panel.css(ink, focus >= 0 ? 0.05 : 0.11)
                                ctx.lineWidth = (lit ? 1.4 : 1) / stage.scale
                                ctx.beginPath()
                                ctx.moveTo(a.x * w, a.y * h)
                                ctx.lineTo(b.x * w, b.y * h)
                                ctx.stroke()
                            }
                        }
                    }
                    Connections { target: stage; function onScaleChanged() { edges.requestPaint() } }

                    // Community names, at each ring's top.
                    Repeater {
                        model: panel.graph.communities || []
                        delegate: Text {
                            required property var modelData
                            required property int index
                            readonly property var members: panel.files.filter(f => f.community === modelData.id)
                            readonly property real cx: members.length ? members.reduce((s, f) => s + f.x, 0) / members.length : 0
                            readonly property real cy: members.length ? members.reduce((s, f) => s + f.y, 0) / members.length : 0
                            readonly property real r: members.length ? Math.max(...members.map(f => Math.hypot(f.x - cx, f.y - cy))) + 0.035 : 0
                            visible: members.length >= 3
                            x: cx * stage.width - width / 2
                            y: (cy - r) * stage.height - height - 2 / stage.scale
                            scale: 1 / stage.scale
                            transformOrigin: Item.Bottom
                            text: "# " + Style.pad(index + 1) + " " + modelData.label
                            color: Style.faint
                            font.family: Style.mono
                            font.variableAxes: Style.narrow
                            font.pixelSize: 10
                        }
                    }

                    // The files.
                    Repeater {
                        model: panel.files
                        delegate: Item {
                            id: node
                            required property var modelData
                            required property int index
                            readonly property int heat: panel.heat(modelData.path)
                            readonly property bool chosen: panel.selected === index
                            readonly property bool near: panel.neighbours[index] === true
                            readonly property bool dimmed: panel.focusIndex >= 0 && !chosen && !near && panel.focusIndex !== index
                            readonly property real size: (5 + Math.sqrt(modelData.symbols) * 1.7) / stage.scale
                            x: modelData.x * stage.width - size / 2
                            y: modelData.y * stage.height - size / 2
                            width: size
                            height: size
                            z: chosen ? 3 : near ? 2 : 1
                            opacity: dimmed ? 0.35 : 1

                            Rectangle {
                                anchors.fill: parent
                                // Touched files in the accent, brighter the more cycles
                                // touched them; the rest in ink.
                                color: node.heat > 0 ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b,
                                                               0.45 + 0.55 * node.heat / Math.max(1, panel.hottest))
                                     : node.chosen || node.near ? Style.text : Style.text2
                                border.color: node.chosen ? theme.accent : Style.bg
                                border.width: 1 / stage.scale
                            }
                            Brackets {
                                visible: node.chosen
                                anchors.fill: parent
                                anchors.margins: -5 / stage.scale
                                size: 5 / stage.scale
                                weight: Math.max(1, 1 / stage.scale)
                            }
                            // Names show for the bigger files, and for what's in focus.
                            Text {
                                visible: node.chosen || node.near || nodeHover.hovered || node.heat > 0
                                         || node.modelData.symbols * stage.scale >= 24
                                x: parent.width + 5 / stage.scale
                                y: (parent.height - height * scale) / 2
                                scale: 1 / stage.scale
                                transformOrigin: Item.TopLeft
                                text: panel.baseName(node.modelData.path)
                                color: node.chosen ? theme.accent : node.heat > 0 ? Style.text : node.near ? Style.text2 : Style.dim
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 10
                            }
                            HoverHandler {
                                id: nodeHover
                                margin: 4
                                cursorShape: Qt.PointingHandCursor
                                onHoveredChanged: panel.hovered = hovered ? node.index : (panel.hovered === node.index ? -1 : panel.hovered)
                            }
                            TapHandler { onTapped: panel.select(node.chosen ? -1 : node.index) }
                        }
                    }
                }

                DragHandler {
                    target: stage
                    acceptedButtons: Qt.LeftButton
                    cursorShape: active ? Qt.ClosedHandCursor : Qt.ArrowCursor
                }
                WheelHandler {
                    onWheel: (event) => stage.zoom(event.angleDelta.y > 0 ? 1.15 : 1 / 1.15, event.x, event.y)
                }

                // Legend and zoom, in the corner.
                Row {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 12
                    spacing: 14
                    visible: panel.files.length > 0
                    Repeater {
                        model: [
                            { swatch: Style.text2, label: qsTr("File, sized by its symbols") },
                            { swatch: theme.accent, label: panel.workBy === "" ? qsTr("Changed by operations") : qsTr("Changed by this operation") }
                        ]
                        delegate: Row {
                            required property var modelData
                            spacing: 6
                            Rectangle { width: 8; height: 8; anchors.verticalCenter: parent.verticalCenter; color: modelData.swatch }
                            Text { text: modelData.label; color: Style.dim; font.family: Style.body; font.pixelSize: 11 }
                        }
                    }
                }
                Row {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 10
                    spacing: 6
                    visible: panel.files.length > 0
                    TacticalButton { text: "−"; implicitWidth: 34; implicitHeight: 30; onClicked: stage.zoom(1 / 1.3, frame.width / 2, frame.height / 2) }
                    TacticalButton { text: qsTr("Fit"); implicitHeight: 30; onClicked: stage.fit() }
                    TacticalButton { text: "+"; implicitWidth: 34; implicitHeight: 30; onClicked: stage.zoom(1.3, frame.width / 2, frame.height / 2) }
                }

                // What's in the way of a map: no graphify, no graph yet, a build
                // underway, or one that failed.
                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(440, parent.width - 48)
                    visible: panel.files.length === 0
                    spacing: 12
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: ops.graphify.length === 0 ? qsTr("graphify isn't installed")
                            : panel.project.length === 0 ? qsTr("No project to map yet")
                            : panel.state === "building" ? qsTr("Mapping %1…").arg(panel.baseName(panel.project))
                            : panel.state === "failed" ? qsTr("The map couldn't be built")
                            : qsTr("%1 isn't mapped yet").arg(panel.baseName(panel.project))
                        wrapMode: Text.Wrap
                        color: Style.text
                        font.family: Style.display
                        font.pixelSize: 22
                        font.weight: Font.DemiBold
                        font.letterSpacing: -0.4
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: ops.graphify.length === 0
                              ? (ops.graphifyInstall.length > 0 && ops.graphifyInstall !== "installing" ? ops.graphifyInstall
                                 : qsTr("graphify reads a project's code and maps how its files and symbols connect, locally and with no API key. Fireteam can install it in its own folder, or install graphifyy yourself with uv or pip."))
                            : panel.state === "failed" ? panel.graph.error
                            : panel.state === "building" ? qsTr("Reading the code. Small projects take a few seconds.")
                            : qsTr("The map is kept in Fireteam's data folder, not in the project, and agents working here get a summary of it.")
                        wrapMode: Text.Wrap
                        color: panel.state === "failed" ? Style.danger : Style.dim
                        font.family: Style.body
                        font.pixelSize: 13
                        lineHeight: 1.2
                    }
                    TacticalButton {
                        Layout.alignment: Qt.AlignHCenter
                        visible: ops.graphify.length === 0
                        enabled: ops.graphifyInstall !== "installing"
                        primary: true
                        text: ops.graphifyInstall === "installing" ? qsTr("Installing graphify…") : qsTr("Install graphify")
                        onClicked: ops.installGraphify()
                    }
                    TacticalButton {
                        Layout.alignment: Qt.AlignHCenter
                        visible: ops.graphify.length > 0 && panel.project.length > 0 && panel.state !== "building"
                        primary: true
                        text: panel.state === "failed" ? qsTr("Try again") : qsTr("Map")
                        onClicked: ops.buildGraph(panel.project)
                    }
                }
            }

            // The file in focus: what it holds, what it leans on, who changed it.
            ColumnLayout {
                visible: panel.selected >= 0 && sheet.width > 1000
                Layout.preferredWidth: 280
                Layout.maximumWidth: 280
                Layout.fillHeight: true
                spacing: 10
                readonly property var file: panel.selected >= 0 ? panel.files[panel.selected] : null

                Text {
                    text: "# " + qsTr("File").toLowerCase()
                    color: Style.dim
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 11
                }
                Text {
                    Layout.fillWidth: true
                    text: parent.file ? panel.baseName(parent.file.path) : ""
                    elide: Text.ElideRight
                    color: Style.text
                    font.family: Style.mono
                    font.variableAxes: Style.wide
                    font.pixelSize: 18
                }
                Text {
                    Layout.fillWidth: true
                    text: parent.file ? parent.file.path : ""
                    elide: Text.ElideMiddle
                    color: Style.dim
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 11
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: parent.parent.file ? (panel.activity[parent.parent.file.path] || []) : []
                        delegate: Chip {
                            required property var modelData
                            text: modelData.codename + " · " + qsTr("%n cycle(s)", "", modelData.cycles)
                            tone: theme.accent
                            marked: true
                        }
                    }
                }
                SectionLabel { Layout.fillWidth: true; Layout.topMargin: 4; text: qsTr("Symbols"); detail: parent.file ? "" + parent.file.symbols : "" }
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 80
                    clip: true
                    model: panel.detail.symbols || []
                    ScrollBar.vertical: ScrollBar {}
                    delegate: RowLayout {
                        required property var modelData
                        width: ListView.view.width - 8
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: modelData.label
                            elide: Text.ElideRight
                            color: Style.text2
                            font.family: Style.mono
                            font.variableAxes: Style.narrow
                            font.pixelSize: 12
                        }
                        Text {
                            text: modelData.line > 0 ? "L" + modelData.line : ""
                            color: Style.faint
                            font.family: Style.mono
                            font.variableAxes: Style.narrow
                            font.pixelSize: 10
                        }
                    }
                }
                SectionLabel { Layout.fillWidth: true; text: qsTr("Linked files") }
                Repeater {
                    model: (panel.detail.neighbours || []).slice(0, 6)
                    delegate: RowLayout {
                        id: neighbour
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: neighbour.modelData.path
                            elide: Text.ElideMiddle
                            color: neighbourHover.hovered ? theme.accent : Style.text2
                            font.family: Style.mono
                            font.variableAxes: Style.narrow
                            font.pixelSize: 11
                            HoverHandler { id: neighbourHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: panel.select(panel.indexOf(neighbour.modelData.path)) }
                        }
                        Text {
                            text: neighbour.modelData.weight
                            color: Style.dim
                            font.family: Style.mono
                            font.variableAxes: Style.narrow
                            font.pixelSize: 10
                        }
                    }
                }
                TacticalButton {
                    Layout.fillWidth: true
                    text: qsTr("Open file")
                    onClicked: Qt.openUrlExternally("file://" + panel.project + "/" + parent.file.path)
                }
            }
        }
    }

    Shortcut { enabled: panel.visible; sequences: ["+", "="]; context: Qt.ApplicationShortcut; onActivated: stage.zoom(1.3, frame.width / 2, frame.height / 2) }
    Shortcut { enabled: panel.visible; sequence: "-"; context: Qt.ApplicationShortcut; onActivated: stage.zoom(1 / 1.3, frame.width / 2, frame.height / 2) }
    Shortcut { enabled: panel.visible; sequence: "0"; context: Qt.ApplicationShortcut; onActivated: stage.fit() }
}
