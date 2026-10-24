import QtQuick
import QtQuick.Layouts

// The board as a theatre map: base camp in the middle, each project a site at
// a fixed bearing (from its path), and each operation a marker at its site.
// Deployed operations pulse and are linked back to camp.
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
    // Places every marker: a site per directory, and the operations at a site
    // spread on a small ring around it.
    function layout() {
        const count = markers.count
        const groups = {}
        for (let i = 0; i < count; ++i) {
            const item = markers.itemAt(i)
            if (!item) continue
            (groups[item.directory] = groups[item.directory] || []).push(item)
        }
        const w = field.width, h = field.height
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
            }
        }
        links.requestPaint()
    }

    onWidthChanged: Qt.callLater(layout)
    onHeightChanged: Qt.callLater(layout)

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
                color: Qt.rgba(0, 0, 0, 0.35)
                border.color: Style.line
                radius: theme.radius
            }

            // Range rings and bearings around base camp, and grid references.
            Canvas {
                id: rings
                anchors.fill: parent
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const cx = width / 2, cy = height / 2
                    ctx.strokeStyle = "rgba(255,255,255,0.06)"
                    ctx.lineWidth = 1
                    for (let r = 1; r <= 4; ++r) {
                        ctx.beginPath()
                        ctx.ellipse(cx - r * (width / 2 - 120) / 4 * 1.1, cy - r * (height / 2 - 70) / 4 * 1.1,
                                    r * (width - 240) / 4 * 1.1, r * (height - 140) / 4 * 1.1)
                        ctx.stroke()
                    }
                    for (let a = 0; a < 360; a += 30) {
                        const t = a * Math.PI / 180
                        ctx.beginPath()
                        ctx.moveTo(cx + Math.cos(t) * 30, cy + Math.sin(t) * 30)
                        ctx.lineTo(cx + Math.cos(t) * width, cy + Math.sin(t) * width)
                        ctx.stroke()
                    }
                    ctx.fillStyle = "rgba(255,255,255,0.18)"
                    ctx.font = "10px monospace"
                    const letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                    for (let i = 0; i * 96 < width; ++i)
                        ctx.fillText(letters[i % letters.length], i * 96 + 8, 16)
                    for (let j = 1; j * 96 < height; ++j)
                        ctx.fillText("" + j, 8, j * 96 + 4)
                }
            }

            // Supply lines from camp to every deployed operation, marching.
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
                        ctx.strokeStyle = live ? theme.accent : "rgba(255,255,255,0.08)"
                        ctx.globalAlpha = live ? 0.75 : 1
                        ctx.lineWidth = live ? 1.5 : 1
                        ctx.setLineDash(live ? [6, 6] : [2, 6])
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

            // Base camp.
            Item {
                x: field.width / 2
                y: field.height / 2
                Rectangle {
                    anchors.centerIn: parent
                    width: 18; height: 18
                    color: "transparent"
                    border.color: Style.text
                    border.width: 2
                    Rectangle { anchors.centerIn: parent; width: 6; height: 6; color: Style.text }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 16
                    text: qsTr("Base camp")
                    color: Style.dim
                    font.family: Style.mono
                    font.pixelSize: 10
                    font.letterSpacing: 3
                    font.capitalization: Font.AllUppercase
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
                    readonly property bool chosen: index === map.currentRow
                    readonly property bool live: status === "deployed"
                    readonly property color tone: Style.statusColor(status, theme.accent)

                    x: cx
                    y: cy
                    Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    onXChanged: links.requestPaint()
                    onYChanged: links.requestPaint()
                    onStatusChanged: links.requestPaint()

                    // Expanding rings while an agent is in the field.
                    Repeater {
                        model: marker.live ? 2 : 0
                        delegate: Rectangle {
                            required property int index
                            anchors.centerIn: parent
                            width: 64; height: 64; radius: 32
                            color: "transparent"
                            border.color: marker.tone
                            border.width: 1.5
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
                    // Selection brackets.
                    Repeater {
                        model: marker.chosen ? 4 : 0
                        delegate: Item {
                            required property int index
                            readonly property bool east: index % 2 === 1
                            readonly property bool south: index >= 2
                            x: east ? 12 : -24
                            y: south ? 12 : -24
                            width: 12; height: 12
                            Rectangle { x: parent.east ? parent.width - 2 : 0; width: 2; height: parent.height; color: theme.accent }
                            Rectangle { y: parent.south ? parent.height - 2 : 0; width: parent.width; height: 2; color: theme.accent }
                        }
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: marker.chosen ? 16 : 12
                        height: width
                        rotation: 45
                        color: marker.live || marker.chosen ? marker.tone : "transparent"
                        border.color: marker.tone
                        border.width: 2
                        Behavior on width { NumberAnimation { duration: 160 } }
                    }

                    Column {
                        x: 22
                        y: -20
                        spacing: 1
                        Text {
                            text: marker.codename
                            color: marker.chosen ? theme.accent : Style.text
                            font.family: Style.display
                            font.pixelSize: 15
                            font.weight: Font.Black
                            font.letterSpacing: 2
                        }
                        Text {
                            text: qsTr("%1 · C%2/%3").arg(Style.statusLabel(marker.status).toUpperCase())
                                      .arg(marker.cyclesDone).arg(marker.cycles)
                            color: marker.tone
                            font.family: Style.mono
                            font.pixelSize: 10
                        }
                        ActivityPulse {
                            visible: marker.live
                            width: 80
                            height: 14
                            events: marker.events
                            live: marker.live
                        }
                    }
                    Text {
                        visible: marker.site
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 30
                        text: "▸ " + map.siteName(marker.directory)
                        color: Style.faint
                        font.family: Style.mono
                        font.pixelSize: 10
                        font.letterSpacing: 1
                    }

                    MouseArea {
                        x: -24; y: -24
                        width: 160; height: 56
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onEntered: Sfx.play("tick")
                        onClicked: map.picked(marker.index)
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 60
                visible: markers.count === 0
                text: qsTr("No operations in the theatre")
                color: Style.faint
                font.family: Style.display
                font.pixelSize: 14
                font.letterSpacing: 4
                font.capitalization: Font.AllUppercase
            }
        }
        // The selected operation, as a field card under the map.
        Rectangle {
            visible: map.selected !== null
            Layout.fillWidth: true
            implicitHeight: card.implicitHeight + 24
            color: Qt.rgba(0.03, 0.04, 0.05, 0.92)
            border.color: Style.line
            radius: theme.radius
            Rectangle { width: 3; height: parent.height; color: map.selected ? Style.statusColor(map.selected.status, theme.accent) : Style.dim }
            RowLayout {
                id: card
                anchors.fill: parent
                anchors.margins: 12
                anchors.leftMargin: 18
                spacing: 18
                Text {
                    text: map.selected ? map.selected.codename : ""
                    color: Style.text
                    font.family: Style.display
                    font.pixelSize: 22
                    font.weight: Font.Black
                    font.letterSpacing: 3
                }
                Text {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: !map.selected ? ""
                        : map.selected.status === "deployed" && map.selected.activity ? "▸ " + map.selected.activity
                        : map.selected.objective
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    color: map.selected && map.selected.status === "deployed" ? theme.accent : Style.dim
                    font.family: Style.mono
                    font.pixelSize: 11
                    textFormat: Text.PlainText
                }
                RowLayout {
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
