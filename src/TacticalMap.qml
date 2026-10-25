import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

// The board as a theatre map: a generated survey sheet with base camp in the
// middle, each project a site at a fixed bearing (from its path), and each
// operation a pin at its site with a tag. Deployed operations pulse and are
// linked back to camp.
Item {
    id: map
    property int currentRow: -1
    property var selected: null
    signal picked(int row)

    function hash(text) {
        let h = 2166136261
        for (let i = 0; i < text.length; ++i)
            h = Math.imul(h ^ text.charCodeAt(i), 16777619)
        return h >>> 0
    }
    function siteName(path) {
        const parts = path.split("/").filter(p => p.length > 0)
        return parts.length ? parts[parts.length - 1] : "/"
    }
    // The kind of pin: in the field, waiting to go, or done with.
    function kind(status) {
        switch (status) {
        case "deployed":
        case "staged":
        case "held":
        case "pinned":
        case "interrupted": return "disc"
        case "complete":
        case "failed":
        case "aborted": return "triangle"
        }
        return "diamond"
    }
    // Canvas wants CSS colours; tokens may be strings or carry alpha.
    function css(value, alpha) {
        const c = Qt.lighter(value, 1.0)
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + ","
             + (alpha === undefined ? c.a : alpha) + ")"
    }
    // Places every marker: a site per directory, and the operations at a site
    // spread on a small ring around it. Then tags are turned or nudged so no
    // two overlap.
    function layout() {
        const count = markers.count
        const groups = {}
        for (let i = 0; i < count; ++i) {
            const item = markers.itemAt(i)
            if (!item) continue
            (groups[item.directory] = groups[item.directory] || []).push(item)
        }
        const w = field.width, h = field.height
        const placed = []
        for (const dir in groups) {
            const angle = (hash(dir) % 3600) / 3600 * Math.PI * 2
            const reach = 0.5 + (hash(dir + "#") % 1000) / 1000 * 0.35
            const sx = w / 2 + Math.cos(angle) * reach * (w / 2 - 120)
            const sy = h / 2 + Math.sin(angle) * reach * (h / 2 - 70)
            const group = groups[dir]
            for (let k = 0; k < group.length; ++k) {
                const spread = group.length > 1 ? 46 : 0
                const a = angle + Math.PI / 2 + k * Math.PI * 2 / group.length
                group[k].cx = sx + Math.cos(a) * spread
                group[k].cy = sy + Math.sin(a) * spread
                group[k].site = k === 0
                placed.push(group[k])
            }
        }
        // Tags: right of the pin by default, left if that's clear instead,
        // else stepped down until clear.
        placed.sort((a, b) => a.cy - b.cy || a.cx - b.cx)
        const boxes = []
        const hits = (r) => boxes.some(b => r.x < b.x + b.w + 6 && b.x < r.x + r.w + 6 && r.y < b.y + b.h + 4 && b.y < r.y + r.h + 4)
        for (const m of placed) {
            const tw = m.tagWidth, th = 24
            const right = (dy) => ({ x: m.cx + 16, y: m.cy - th / 2 + dy, w: tw, h: th })
            const left = (dy) => ({ x: m.cx - 16 - tw, y: m.cy - th / 2 + dy, w: tw, h: th })
            const roomRight = m.cx + 16 + tw < w - 8
            let choice = null
            for (let step = 0; step < 6 && !choice; ++step) {
                const dy = step * (th + 4)
                if (roomRight && !hits(right(dy))) choice = { left: false, dy: dy }
                else if (!hits(left(dy))) choice = { left: true, dy: dy }
            }
            if (!choice) choice = { left: !roomRight, dy: 0 }
            m.tagLeft = choice.left
            m.tagShift = choice.dy
            boxes.push(choice.left ? left(choice.dy) : right(choice.dy))
        }
        links.requestPaint()
    }

    onWidthChanged: Qt.callLater(layout)
    onHeightChanged: Qt.callLater(layout)

    Connections {
        target: theme
        function onChanged() { survey.requestPaint(); links.requestPaint() }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        SectionLabel {
            Layout.fillWidth: true
            text: qsTr("Theatre")
            detail: qsTr("%1 deployed · %2 operations").arg(Style.pad(ops.deployedCount)).arg(Style.pad(markers.count))
        }

        Item {
            id: field
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Rectangle {
                anchors.fill: parent
                color: Style.bg
                border.color: Style.line
                radius: theme.radius
            }

            // The survey: contours traced from seeded noise by marching
            // squares, every fifth heavier and labelled, over a sheet grid
            // with its references along the edges.
            Canvas {
                id: survey
                anchors.fill: parent
                anchors.margins: 1
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    if (width < 4 || height < 4) return

                    // Seeded value noise, the same land on every paint.
                    const rand = (ix, iy) => {
                        let h = Math.imul(ix, 374761393) + Math.imul(iy, 668265263) + 1442695041
                        h = Math.imul(h ^ (h >>> 13), 1274126177)
                        return ((h ^ (h >>> 16)) >>> 0) / 4294967295
                    }
                    const smooth = t => t * t * (3 - 2 * t)
                    const noise = (x, y) => {
                        const ix = Math.floor(x), iy = Math.floor(y)
                        const fx = smooth(x - ix), fy = smooth(y - iy)
                        const a = rand(ix, iy), b = rand(ix + 1, iy), c = rand(ix, iy + 1), d = rand(ix + 1, iy + 1)
                        return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy
                    }
                    const cell = 14
                    const cols = Math.ceil(width / cell) + 1, rows = Math.ceil(height / cell) + 1
                    const v = []
                    for (let j = 0; j < rows; ++j) {
                        const row = []
                        for (let i = 0; i < cols; ++i) {
                            const x = i * cell / 330, y = j * cell / 330
                            row.push(noise(x, y) * 0.62 + noise(x * 2.3 + 17, y * 2.3 + 5) * 0.28
                                     + noise(x * 5.1 + 3, y * 5.1 + 11) * 0.10)
                        }
                        v.push(row)
                    }

                    // The grid of the sheet, and its references.
                    const grid = 96
                    ctx.strokeStyle = map.css(Style.line, 0.55)
                    ctx.lineWidth = 1
                    ctx.beginPath()
                    for (let x = grid; x < width; x += grid) { ctx.moveTo(x + 0.5, 0); ctx.lineTo(x + 0.5, height) }
                    for (let y = grid; y < height; y += grid) { ctx.moveTo(0, y + 0.5); ctx.lineTo(width, y + 0.5) }
                    ctx.stroke()

                    // Contours.
                    const levels = 14
                    for (let l = 1; l < levels; ++l) {
                        const t = 0.2 + l * 0.045
                        const index = l % 5 === 0
                        ctx.strokeStyle = index ? map.css(Style.lineStrong, 0.9) : map.css(Style.lineStrong, 0.4)
                        ctx.lineWidth = index ? 1.2 : 0.8
                        ctx.beginPath()
                        let label = null
                        for (let j = 0; j < rows - 1; ++j) {
                            for (let i = 0; i < cols - 1; ++i) {
                                const a = v[j][i], b = v[j][i + 1], c = v[j + 1][i + 1], d = v[j + 1][i]
                                const code = (a > t ? 8 : 0) | (b > t ? 4 : 0) | (c > t ? 2 : 0) | (d > t ? 1 : 0)
                                if (code === 0 || code === 15) continue
                                const x = i * cell, y = j * cell
                                const top = [x + cell * (t - a) / (b - a), y]
                                const right = [x + cell, y + cell * (t - b) / (c - b)]
                                const bottom = [x + cell * (t - d) / (c - d), y + cell]
                                const left = [x, y + cell * (t - a) / (d - a)]
                                const seg = (p, q) => {
                                    ctx.moveTo(p[0], p[1]); ctx.lineTo(q[0], q[1])
                                    if (index && !label && p[0] > 120 && p[0] < width - 120 && p[1] > 60 && p[1] < height - 40
                                            && (i * 7 + j * 13 + l) % 23 === 0)
                                        label = p
                                }
                                switch (code) {
                                case 1: case 14: seg(left, bottom); break
                                case 2: case 13: seg(bottom, right); break
                                case 3: case 12: seg(left, right); break
                                case 4: case 11: seg(top, right); break
                                case 6: case 9: seg(top, bottom); break
                                case 7: case 8: seg(left, top); break
                                case 5: seg(left, top); seg(bottom, right); break
                                case 10: seg(top, right); seg(left, bottom); break
                                }
                            }
                        }
                        ctx.stroke()
                        if (label) {
                            const text = "" + (100 + l * 25)
                            ctx.font = "9px 'Martian Mono'"
                            const tw = ctx.measureText(text).width
                            ctx.fillStyle = map.css(Style.bg, 1)
                            ctx.fillRect(label[0] - tw / 2 - 3, label[1] - 6, tw + 6, 12)
                            ctx.fillStyle = map.css(Style.faint, 1)
                            ctx.fillText(text, label[0] - tw / 2, label[1] + 3)
                        }
                    }

                    // Grid references along the top and left edges.
                    ctx.font = "9px 'Martian Mono'"
                    ctx.fillStyle = map.css(Style.faint, 1)
                    const letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                    for (let i = 0; i * grid < width; ++i)
                        ctx.fillText(letters[i % letters.length], i * grid + 8, 15)
                    for (let j = 1; j * grid < height; ++j)
                        ctx.fillText(Style.pad(j), 6, j * grid - 6)
                }
            }

            // Supply lines from camp to every operation; deployed ones march.
            Canvas {
                id: links
                anchors.fill: parent
                property real dash: 0
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const cx = width / 2, cy = height / 2
                    for (let i = 0; i < markers.count; ++i) {
                        const m = markers.itemAt(i)
                        if (!m) continue
                        const live = m.status === "deployed"
                        ctx.strokeStyle = live ? map.css(theme.accent, 0.85) : map.css(Style.dim, 0.35)
                        ctx.lineWidth = live ? 1.5 : 1
                        ctx.setLineDash(live ? [6, 6] : [2, 5])
                        ctx.lineDashOffset = live ? -dash : 0
                        ctx.beginPath()
                        ctx.moveTo(cx, cy)
                        ctx.lineTo(m.cx, m.cy)
                        ctx.stroke()
                    }
                }
                Timer {
                    interval: 50
                    repeat: true
                    running: map.visible && ops.deployedCount > 0
                    onTriggered: { links.dash = (links.dash + 1) % 12; links.requestPaint() }
                }
            }

            // Base camp: a square holding with a dot at its centre.
            Item {
                x: field.width / 2
                y: field.height / 2
                Rectangle {
                    anchors.centerIn: parent
                    width: 30; height: 30
                    color: Qt.rgba(Style.bg.r, Style.bg.g, Style.bg.b, 0.7)
                    border.color: Style.text2
                    Rectangle { anchors.centerIn: parent; width: 6; height: 6; color: Style.text }
                }
                Brackets { x: -21; y: -21; width: 42; height: 42; size: 6; color: Style.dim }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 26
                    text: qsTr("Base camp")
                    color: Style.text2
                    font.family: Style.body
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }
            }

            Repeater {
                id: markers
                model: ops
                onCountChanged: Qt.callLater(map.layout)
                delegate: Item {
                    id: marker
                    required property int index
                    required property string codename
                    required property string directory
                    required property string status
                    required property int cyclesDone
                    required property int cycles
                    required property string activity
                    required property int events
                    property real cx: field.width / 2
                    property real cy: field.height / 2
                    property bool site: true
                    property bool tagLeft: false
                    property real tagShift: 0
                    readonly property real tagWidth: tag.width
                    readonly property bool chosen: index === map.currentRow
                    readonly property bool live: status === "deployed"
                    readonly property color tone: Style.statusColor(status, theme.accent)
                    readonly property string shape: map.kind(status)

                    x: cx
                    y: cy
                    z: chosen ? 2 : live ? 1 : 0
                    Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    onXChanged: links.requestPaint()
                    onYChanged: links.requestPaint()
                    onStatusChanged: links.requestPaint()
                    onTagWidthChanged: Qt.callLater(map.layout)

                    // Expanding rings while an agent is in the field.
                    Repeater {
                        model: marker.live ? 2 : 0
                        delegate: Rectangle {
                            required property int index
                            anchors.centerIn: parent
                            width: 64; height: 64; radius: 32
                            color: "transparent"
                            border.color: theme.accent
                            border.width: 1
                            scale: 0.2
                            opacity: 0
                            SequentialAnimation on scale {
                                loops: Animation.Infinite
                                PauseAnimation { duration: index * 900 }
                                NumberAnimation { from: 0.2; to: 1.4; duration: 1800; easing.type: Easing.OutCubic }
                            }
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                PauseAnimation { duration: index * 900 }
                                NumberAnimation { from: 0.9; to: 0; duration: 1800 }
                            }
                        }
                    }

                    // A leader from the pin to its tag when the tag was nudged.
                    Rectangle {
                        visible: marker.tagShift > 0
                        x: marker.tagLeft ? -12 : 8
                        width: 1
                        height: marker.tagShift
                        color: Style.lineStrong
                    }

                    // The pin: a disc in ink with its kind cut into it; the
                    // selected one in the accent, with corner marks.
                    Rectangle {
                        id: pin
                        anchors.centerIn: parent
                        width: 18; height: 18; radius: 9
                        color: marker.chosen ? theme.accent : Style.text
                        border.color: Style.bg
                        border.width: 1
                        readonly property color cut: marker.chosen ? theme.accentForeground : Style.bg
                        Rectangle {
                            visible: marker.shape === "disc"
                            anchors.centerIn: parent
                            width: 6; height: 6; radius: 3
                            color: pin.cut
                        }
                        Rectangle {
                            visible: marker.shape === "diamond"
                            anchors.centerIn: parent
                            width: 6; height: 6
                            rotation: 45
                            color: pin.cut
                        }
                        Shape {
                            visible: marker.shape === "triangle"
                            anchors.centerIn: parent
                            width: 8; height: 7
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                strokeWidth: -1
                                fillColor: pin.cut
                                PathPolyline { path: [Qt.point(4, 0), Qt.point(8, 7), Qt.point(0, 7), Qt.point(4, 0)] }
                            }
                        }
                    }
                    Brackets {
                        visible: marker.chosen
                        x: -17; y: -17
                        width: 34; height: 34
                        size: 7
                    }

                    // The tag: callsign and cycles in mono, its status as a square.
                    Rectangle {
                        id: tag
                        x: marker.tagLeft ? -16 - width : 16
                        y: -height / 2 + marker.tagShift
                        width: tagRow.implicitWidth + 18
                        height: 24
                        radius: Math.min(2, theme.radius)
                        color: marker.chosen ? Style.wash : hover.containsMouse ? Style.raised : Style.panel
                        border.color: marker.chosen ? theme.accent : Style.lineStrong
                        Row {
                            id: tagRow
                            anchors.verticalCenter: parent.verticalCenter
                            x: 9
                            spacing: 7
                            Rectangle {
                                id: tagDot
                                anchors.verticalCenter: parent.verticalCenter
                                width: 6; height: 6
                                color: marker.tone
                                SequentialAnimation on opacity {
                                    running: marker.live
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.15; duration: 450 }
                                    NumberAnimation { to: 1; duration: 450 }
                                    onStopped: tagDot.opacity = 1
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: marker.codename
                                color: marker.chosen ? Style.text : Style.text2
                                font.family: Style.mono
                                font.variableAxes: Style.wide
                                font.pixelSize: 11
                                font.letterSpacing: -0.2
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: marker.cyclesDone + "/" + marker.cycles
                                color: Style.dim
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 10
                                font.features: { "tnum": 1 }
                            }
                            ActivityPulse {
                                visible: marker.live
                                anchors.verticalCenter: parent.verticalCenter
                                width: visible ? 44 : 0
                                height: 12
                                events: marker.events
                                live: marker.live
                            }
                        }
                    }

                    // The site's name, set beneath it as a surveyor would.
                    Text {
                        visible: marker.site
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 16
                        text: map.siteName(marker.directory)
                        color: Style.dim
                        font.family: Style.body
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        font.italic: true
                    }

                    MouseArea {
                        id: hover
                        x: Math.min(-14, tag.x)
                        y: Math.min(-14, tag.y)
                        width: Math.max(14, tag.x + tag.width) - x
                        height: Math.max(14, tag.y + tag.height) - y
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onEntered: Sfx.play("tick")
                        onClicked: map.picked(marker.index)
                    }
                }
            }

            // The key to the pins, in the sheet's corner.
            Rectangle {
                visible: markers.count > 0
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 12
                width: legend.implicitWidth + 20
                height: 28
                color: Style.panel
                border.color: Style.line
                radius: Math.min(2, theme.radius)
                Row {
                    id: legend
                    anchors.centerIn: parent
                    spacing: 16
                    Repeater {
                        model: [{ shape: "disc", status: "deployed" }, { shape: "diamond", status: "standby" },
                                { shape: "triangle", status: "complete" }]
                        delegate: Row {
                            required property var modelData
                            spacing: 6
                            Rectangle {
                                id: key
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14; height: 14; radius: 7
                                color: Style.text2
                                Rectangle {
                                    visible: modelData.shape !== "triangle"
                                    anchors.centerIn: parent
                                    width: 5; height: 5
                                    radius: modelData.shape === "disc" ? 2.5 : 0
                                    rotation: modelData.shape === "diamond" ? 45 : 0
                                    color: Style.panel
                                }
                                Shape {
                                    visible: modelData.shape === "triangle"
                                    anchors.centerIn: parent
                                    width: 6; height: 5
                                    preferredRendererType: Shape.CurveRenderer
                                    ShapePath {
                                        strokeWidth: -1
                                        fillColor: Style.panel
                                        PathPolyline { path: [Qt.point(3, 0), Qt.point(6, 5), Qt.point(0, 5), Qt.point(3, 0)] }
                                    }
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Style.statusLabel(modelData.status)
                                color: Style.dim
                                font.family: Style.body
                                font.pixelSize: 11
                            }
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 60
                visible: markers.count === 0
                text: qsTr("No operations in the theatre")
                color: Style.dim
                font.family: Style.body
                font.pixelSize: 14
            }
        }
        // The selected operation, as a field card under the map.
        Rectangle {
            visible: map.selected !== null
            Layout.fillWidth: true
            implicitHeight: card.implicitHeight + 24
            color: Style.panel
            border.color: Style.line
            radius: theme.radius
            Rectangle { width: 2; height: parent.height; color: theme.accent }
            RowLayout {
                id: card
                anchors.fill: parent
                anchors.margins: 12
                anchors.leftMargin: 18
                spacing: 16
                Text {
                    text: map.selected ? map.selected.codename : ""
                    color: Style.text
                    font.family: Style.mono
                    font.variableAxes: Style.wide
                    font.pixelSize: 18
                    font.letterSpacing: -0.4
                }
                Chip {
                    visible: map.selected !== null && card.width > 640
                    marked: true
                    mono: true
                    tone: map.selected ? Style.statusColor(map.selected.status, theme.accent) : Style.dim
                    text: map.selected ? Style.statusLabel(map.selected.status) + " · " + map.selected.cyclesDone + "/" + map.selected.cycles : ""
                }
                Text {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: !map.selected ? ""
                        : map.selected.status === "deployed" && map.selected.activity ? "▸ " + map.selected.activity
                        : map.selected.objective
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    color: map.selected && map.selected.status === "deployed" ? theme.accent : Style.text2
                    font.family: map.selected && map.selected.status === "deployed" ? Style.mono : Style.body
                    font.variableAxes: map.selected && map.selected.status === "deployed" ? Style.narrow : ({})
                    font.pixelSize: map.selected && map.selected.status === "deployed" ? 11 : 13
                    textFormat: Text.PlainText
                }
                RowLayout {
                    visible: card.width > 860
                    spacing: 14
                    KeyHint { key: qsTr("Space"); label: qsTr("Deploy") }
                    KeyHint { key: "T"; label: qsTr("Orders") }
                    KeyHint { key: "V"; label: qsTr("Intel") }
                    KeyHint { key: "M"; label: qsTr("Board") }
                }
            }
        }
    }
}
