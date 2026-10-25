import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// The in-app reader for a debrief, review or hand-off brief. Reports are
// agent-written, so they're shown through Qt's rich text subset (no scripts,
// no network, no images) with their own styling stripped and the reader's
// typography in its place.
Item {
    id: panel
    visible: false

    property string path: ""
    property string title: ""
    property string format: ""
    property string source: ""
    property bool failed: false
    // The reading size, kept for this session only.
    property int readSize: 15
    property var matches: []
    property int matchIndex: -1

    readonly property string fileName: {
        const parts = panel.path.split("/")
        return parts.length > 0 ? parts[parts.length - 1] : ""
    }

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius

    function open(path, title) {
        panel.path = path || ""
        panel.title = title || ""
        const data = panel.path.length > 0 ? ops.readReport(panel.path) : ({})
        panel.failed = !data || data.format === undefined
        panel.format = panel.failed ? "" : data.format
        panel.source = panel.failed ? "" : (data.text || "")
        find.text = ""
        panel.matches = []
        panel.matchIndex = -1
        prepare()
        render()
        visible = true
        enter.restart()
        flick.contentY = 0
        reading.forceActiveFocus()
    }
    function close() {
        visible = false
        doc.text = ""
        panel.prepared = ""
    }

    // Report HTML, cleaned ---------------------------------------------------

    function hex(c) { return String(c) }

    // Takes out everything that isn't content or that would bring its own
    // colours: scripts, styles, embedded objects, images, and colour or style
    // attributes.
    function clean(html) {
        let s = html
        const body = s.match(/<body[^>]*>([\s\S]*)<\/body>/i)
        if (body)
            s = body[1]
        s = s.replace(/<!--[\s\S]*?-->/g, "")
             .replace(/<(script|style|head|title|noscript|iframe|object|svg|math|template|form|select|textarea|button)\b[\s\S]*?<\/\1\s*>/gi, "")
             .replace(/<\/?(script|style|link|meta|base|img|embed|source|video|audio|picture|input|iframe|object|font)\b[^>]*>/gi, "")
             .replace(/<!doctype[^>]*>/gi, "")
             .replace(/<\/?(html|body|head)\b[^>]*>/gi, "")
        // Attributes, inside tags only.
        s = s.replace(/<([a-zA-Z][\w-]*)(\s[^>]*)?>/g, (tag, name, attrs) => {
            if (!attrs)
                return tag
            attrs = attrs.replace(/\s(?:style|bgcolor|color|background|class|border|cellpadding|cellspacing|width|height|align|valign|face|size|on[a-z]+)\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)/gi, "")
            return "<" + name + attrs + ">"
        })
        return s
    }

    // Gives the cleaned HTML the reader's own typography, as inline styles
    // and table attributes, which is what Qt's rich text honours.
    function styled(html) {
        const n = panel.readSize
        const ink = hex(Style.text), ink2 = hex(Style.text2), dim = hex(Style.dim)
        const line = hex(Style.line), accent = hex(theme.accent)
        const mono = "font-family:'" + Style.mono + "';"
        const head = (size, top) => "color:" + ink + "; font-family:'" + Style.display + "'; font-weight:700; font-size:"
                                     + Math.round(size) + "px; margin-top:" + Math.round(top) + "px; margin-bottom:" + Math.round(n * 0.5) + "px;"
        const styles = {
            h1: head(n * 1.7, n * 0.4),
            h2: head(n * 1.3, n * 1.6),
            h3: head(n * 1.1, n * 1.3),
            h4: head(n, n * 1.1), h5: head(n, n), h6: head(n, n),
            p: "line-height:150%; margin-top:0px; margin-bottom:" + Math.round(n * 0.8) + "px;",
            li: "line-height:145%; margin-bottom:" + Math.round(n * 0.2) + "px;",
            ul: "margin-top:0px; margin-bottom:" + Math.round(n * 0.8) + "px;",
            ol: "margin-top:0px; margin-bottom:" + Math.round(n * 0.8) + "px;",
            strong: "color:" + ink + "; font-weight:600;",
            b: "color:" + ink + "; font-weight:600;",
            a: "color:" + accent + ";",
            code: mono + " font-size:" + Math.round(n * 0.82) + "px; color:" + ink + ";",
            kbd: mono + " font-size:" + Math.round(n * 0.82) + "px; color:" + ink + ";",
            pre: mono + " font-size:" + Math.round(n * 0.78) + "px; color:" + ink2 + "; white-space:pre-wrap; margin:0px;",
            th: "color:" + dim + "; font-weight:600; text-align:left; font-size:" + Math.round(n * 0.85) + "px;",
            td: "line-height:130%;",
            div: "margin-bottom:" + Math.round(n * 0.6) + "px;",
            blockquote: "color:" + dim + "; margin-left:" + Math.round(n) + "px;",
            dt: "color:" + ink + "; font-weight:600;",
        }
        let s = html.replace(/<([a-zA-Z][\w-]*)(\s[^>]*)?>/g, (tag, name, attrs) => {
            const key = name.toLowerCase()
            const css = styles[key]
            let extra = ""
            if (key === "table")
                extra = ' border="1" cellspacing="0" cellpadding="' + Math.round(n * 0.5) + '" width="100%"'
                      + ' style="border-collapse:collapse; border-style:solid; border-color:' + line + '; margin-top:4px; margin-bottom:' + Math.round(n) + 'px;"'
            else if (key === "td" || key === "th")
                extra = ' valign="top" style="' + css + '"'
            else if (css)
                extra = ' style="' + css + '"'
            return "<" + name + (attrs || "") + extra + ">"
        })
        // A preformatted block reads as a well: one bordered, padded cell.
        s = s.replace(/<pre\b([^>]*)>([\s\S]*?)<\/pre\s*>/gi, (all, attrs, inner) =>
            '<table border="1" cellspacing="0" cellpadding="' + Math.round(n * 0.75) + '" width="100%"'
            + ' style="border-collapse:collapse; border-style:solid; border-color:' + line + '; margin-top:2px; margin-bottom:' + Math.round(n) + 'px;">'
            + '<tr><td><pre' + attrs + '>' + inner.replace(/<\/?code\b[^>]*>/gi, "") + '</pre></td></tr></table>')
        return s
    }

    // Markdown goes through Qt's own reader (MarkdownText), which turns into
    // HTML when the format is switched to RichText; its spans are then mapped
    // back to plain tags so the reader's typography applies as for HTML.
    function markdownHtml(text) {
        converter.textFormat = TextEdit.MarkdownText
        converter.text = text
        converter.textFormat = TextEdit.RichText
        let h = converter.text
        converter.text = ""
        const body = h.match(/<body[^>]*>([\s\S]*)<\/body>/i)
        if (body)
            h = body[1]
        // Block quotes come out as indented paragraphs.
        h = h.replace(/<p style="[^"]*margin-left:[1-9]\d*px[^"]*">([\s\S]*?)<\/p>/g, "<blockquote><p>$1</p></blockquote>")
        // Fenced code comes out as one monospace paragraph per line.
        h = h.replace(/<p style="[^"]*">\s*<span style="[^"]*font-family:'monospace'[^"]*">([^<]*)<\/span>\s*<\/p>/g, "<pre>$1</pre>")
             .replace(/<\/pre>\s*<pre>/g, "\n")
        // A table's first row is its head.
        h = h.replace(/<table([^>]*)>\s*<tr>([\s\S]*?)<\/tr>/g, (all, attrs, row) =>
                "<table" + attrs + "><tr>" + row.replace(/<td>/g, "<th>").replace(/<\/td>/g, "</th>") + "</tr>")
             .replace(/(<t[dh][^>]*>)\s*<p[^>]*>([\s\S]*?)<\/p>\s*(<\/t[dh]>)/g, "$1$2$3")
        h = h.replace(/<span style="([^"]*)">([\s\S]*?)<\/span>/g, (all, css, inner) => {
            if (/monospace/.test(css)) inner = "<code>" + inner + "</code>"
            if (/font-weight:\s*[6-9]00/.test(css)) inner = "<strong>" + inner + "</strong>"
            if (/font-style:\s*italic/.test(css)) inner = "<em>" + inner + "</em>"
            if (/line-through/.test(css)) inner = "<s>" + inner + "</s>"
            return inner
        })
        return h.replace(/(<h[1-6][^>]*>)<strong>([\s\S]*?)<\/strong>(<\/h[1-6]>)/g, "$1$2$3")
    }

    function escaped(text) {
        return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    // The format's HTML, before the reader's styling (worked out once a file).
    property string prepared: ""

    function prepare() {
        if (panel.failed)
            panel.prepared = ""
        else if (panel.format === "html")
            panel.prepared = clean(panel.source)
        else if (panel.format === "markdown")
            panel.prepared = clean(markdownHtml(panel.source))
        else
            panel.prepared = '<p style="white-space:pre-wrap; line-height:150%; margin:0px;">' + escaped(panel.source) + "</p>"
    }

    function render() {
        const top = flick.contentHeight > 0 ? flick.contentY / flick.contentHeight : 0
        doc.text = panel.failed ? "" : panel.format === "text" ? panel.prepared : styled(panel.prepared)
        Qt.callLater(() => { flick.contentY = Math.max(0, top * flick.contentHeight) })
        if (find.text.length > 0)
            Qt.callLater(() => search(false))
    }

    onReadSizeChanged: if (visible) render()

    // Only web links leave the reader, and only to the browser.
    function follow(link) {
        if (/^https?:\/\//i.test(link))
            Qt.openUrlExternally(link)
    }

    // Find in page -----------------------------------------------------------

    function search(advance) {
        const needle = find.text.toLowerCase()
        if (needle.length === 0) {
            panel.matches = []
            panel.matchIndex = -1
            doc.deselect()
            return
        }
        const plain = doc.getText(0, doc.length).toLowerCase()
        const found = []
        // The plain text can drop the document's table markers, so each hit is
        // walked forward until it lines up with a document position.
        let delta = 0
        for (let i = plain.indexOf(needle); i >= 0 && found.length < 1000; i = plain.indexOf(needle, i + needle.length)) {
            let pos = i + delta
            let tries = 0
            while (tries < 64 && doc.getText(pos, pos + needle.length).toLowerCase() !== needle) { pos++; tries++ }
            if (tries < 64) { delta = pos - i; found.push(pos) }
        }
        panel.matches = found
        if (found.length === 0) {
            panel.matchIndex = -1
            doc.deselect()
            return
        }
        let next = 0
        if (advance && panel.matchIndex >= 0)
            next = (panel.matchIndex + 1) % found.length
        else {
            // The first hit at or after what's on screen.
            const viewTop = flick.contentY - doc.y
            next = found.findIndex(p => doc.positionToRectangle(p).y >= viewTop)
            if (next < 0) next = 0
        }
        show(next)
    }
    function step(by) {
        if (panel.matches.length === 0) { search(false); return }
        show((panel.matchIndex + by + panel.matches.length) % panel.matches.length)
    }
    function show(index) {
        panel.matchIndex = index
        const pos = panel.matches[index]
        doc.select(pos, pos + find.text.length)
        const r = doc.positionToRectangle(pos)
        const y = r.y + doc.y
        if (y < flick.contentY + 24 || y + r.height > flick.contentY + flick.height - 24)
            flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, y - flick.height / 3))
    }

    function scrollBy(dy) {
        flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), flick.contentY + dy))
    }
    function scrollKeys(event) {
        const page = flick.height - 48
        switch (event.key) {
        case Qt.Key_Down: case Qt.Key_J: scrollBy(48); break
        case Qt.Key_Up: case Qt.Key_K: scrollBy(-48); break
        case Qt.Key_PageDown: scrollBy(page); break
        case Qt.Key_Space: scrollBy(event.modifiers & Qt.ShiftModifier ? -page : page); break
        case Qt.Key_PageUp: scrollBy(-page); break
        case Qt.Key_Home: flick.contentY = 0; break
        case Qt.Key_End: scrollBy(flick.contentHeight); break
        case Qt.Key_N: step(event.modifiers & Qt.ShiftModifier ? -1 : 1); break
        default: return
        }
        event.accepted = true
    }

    Shortcut {
        sequence: "/"
        context: Qt.ApplicationShortcut
        enabled: panel.visible && !panel.failed && !find.activeFocus
        onActivated: { find.forceActiveFocus(); find.selectAll() }
    }
    Shortcut {
        sequences: ["Ctrl+=", "Ctrl++"]
        context: Qt.ApplicationShortcut
        enabled: panel.visible
        onActivated: panel.readSize = Math.min(24, panel.readSize + 1)
    }
    Shortcut {
        sequence: "Ctrl+-"
        context: Qt.ApplicationShortcut
        enabled: panel.visible
        onActivated: panel.readSize = Math.max(12, panel.readSize - 1)
    }
    Shortcut {
        sequence: "Ctrl+0"
        context: Qt.ApplicationShortcut
        enabled: panel.visible
        onActivated: panel.readSize = 15
    }

    // Turns markdown into HTML; never shown.
    TextEdit { id: converter; visible: false; textFormat: TextEdit.MarkdownText }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Style.bg.r, Style.bg.g, Style.bg.b, 0.86)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: panel.close() }
    }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(1000, parent.width - 48)
        height: parent.height - 48
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
            anchors.topMargin: 24
            anchors.bottomMargin: 20
            spacing: 0

            // Eyebrow and title, on the reading column.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 36
                Layout.rightMargin: 36
                spacing: 4
                Text {
                    Layout.fillWidth: true
                    text: "# " + qsTr("Reader").toLowerCase() + " // " + panel.fileName
                    elide: Text.ElideMiddle
                    color: Style.dim
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 11
                    textFormat: Text.PlainText
                }
                Text {
                    Layout.fillWidth: true
                    text: panel.title.length > 0 ? panel.title : panel.fileName
                    elide: Text.ElideRight
                    color: Style.text
                    font.family: Style.display
                    font.pixelSize: 26
                    font.weight: Font.DemiBold
                    font.letterSpacing: -0.6
                    textFormat: Text.PlainText
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.topMargin: 16; implicitHeight: 1; color: Style.line }

            // The document.
            Item {
                id: reading
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !panel.failed
                Keys.onPressed: (event) => panel.scrollKeys(event)

                ScrollBar { id: vbar; anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom }
                Flickable {
                    id: flick
                    anchors.fill: parent
                    anchors.rightMargin: 8
                    clip: true
                    contentWidth: width
                    contentHeight: doc.implicitHeight + 56
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: vbar

                    TextEdit {
                        id: doc
                        x: 36
                        y: 26
                        width: flick.width - 64
                        readOnly: true
                        selectByMouse: true
                        persistentSelection: true
                        wrapMode: panel.format === "text" ? TextEdit.WrapAtWordBoundaryOrAnywhere : TextEdit.Wrap
                        textFormat: TextEdit.RichText
                        color: Style.text2
                        selectionColor: theme.accent
                        selectedTextColor: theme.accentForeground
                        font.family: panel.format === "text" ? Style.mono : Style.body
                        font.variableAxes: panel.format === "text" ? Style.narrow : ({})
                        font.pixelSize: panel.format === "text" ? Math.round(panel.readSize * 0.82) : panel.readSize
                        onLinkActivated: (link) => panel.follow(link)
                        Keys.onPressed: (event) => panel.scrollKeys(event)
                        HoverHandler { cursorShape: doc.hoveredLink.length > 0 ? Qt.PointingHandCursor : Qt.IBeamCursor }
                    }
                }
            }

            // Couldn't read it: say so calmly, and offer the browser.
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: panel.failed
                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(460, parent.width - 72)
                    spacing: 8
                    Text {
                        Layout.fillWidth: true
                        text: "# " + qsTr("Not readable here").toLowerCase()
                        color: Style.dim
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                        font.pixelSize: 11
                    }
                    Text {
                        Layout.fillWidth: true
                        text: qsTr("This report can't be shown in the reader")
                        wrapMode: Text.Wrap
                        color: Style.text
                        font.family: Style.body
                        font.pixelSize: 17
                        font.weight: Font.Medium
                    }
                    Text {
                        Layout.fillWidth: true
                        text: qsTr("The file may have moved, or it's outside Fireteam's data folder. Your browser may still open it.")
                        wrapMode: Text.Wrap
                        color: Style.text2
                        font.family: Style.body
                        font.pixelSize: 14
                        lineHeight: 1.2
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        visible: panel.path.length > 0
                        text: panel.path
                        wrapMode: Text.WrapAnywhere
                        color: Style.dim
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                        font.pixelSize: 11
                        textFormat: Text.PlainText
                    }
                    TacticalButton {
                        Layout.topMargin: 12
                        visible: panel.path.length > 0
                        text: qsTr("Open in browser")
                        primary: true
                        onClicked: ops.openReport(panel.path)
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }

            // Where the hovered link goes, or which file this is.
            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 36
                Layout.rightMargin: 36
                Layout.topMargin: 10
                readonly property bool external: /^https?:\/\//i.test(doc.hoveredLink)
                text: doc.hoveredLink.length > 0
                      ? (external ? "→ " + doc.hoveredLink : "→ " + doc.hoveredLink + "  # " + qsTr("not opened: only web links leave the reader"))
                      : panel.path
                elide: Text.ElideMiddle
                color: doc.hoveredLink.length > 0 && external ? theme.accent : Style.dim
                font.family: Style.mono
                font.variableAxes: Style.narrow
                font.pixelSize: 10
                textFormat: Text.PlainText
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 36
                Layout.rightMargin: 36
                Layout.topMargin: 12
                spacing: 10
                TacticalButton { text: qsTr("Close"); key: "Esc"; onClicked: panel.close() }
                TextField {
                    id: find
                    visible: !panel.failed
                    Layout.fillWidth: true
                    Layout.maximumWidth: 240
                    Layout.minimumWidth: 110
                    Layout.preferredHeight: 36
                    Layout.leftMargin: 8
                    placeholderText: qsTr("Find in page  /")
                    Material.background: Style.bg
                    font.family: Style.body
                    font.pixelSize: 13
                    topPadding: 6
                    bottomPadding: 6
                    onTextChanged: panel.search(false)
                    onAccepted: panel.step(1)
                    Keys.onPressed: (event) => {
                        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ShiftModifier)) {
                            panel.step(-1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                            reading.forceActiveFocus()
                            event.accepted = true
                        }
                    }
                }
                Text {
                    visible: !panel.failed && find.text.length > 0
                    text: panel.matches.length === 0 ? qsTr("No matches")
                                                     : qsTr("%1 of %2").arg(panel.matchIndex + 1).arg(panel.matches.length)
                    color: panel.matches.length === 0 ? Style.dim : Style.text2
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 11
                    font.features: { "tnum": 1 }
                }
                Item { Layout.fillWidth: true }
                // The reading size: smaller, the size, larger.
                RowLayout {
                    visible: !panel.failed && sheet.width > 640
                    spacing: 0
                    Repeater {
                        model: [{ label: "A−", by: -1 }, { label: "A+", by: 1 }]
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            implicitWidth: 30
                            implicitHeight: 30
                            color: sizeHover.hovered ? Style.raised : "transparent"
                            border.color: Style.line
                            radius: Math.min(2, theme.radius)
                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData.label
                                color: sizeHover.hovered ? Style.text : Style.dim
                                font.family: Style.body
                                font.pixelSize: parent.index === 0 ? 11 : 14
                                font.weight: Font.Medium
                            }
                            HoverHandler { id: sizeHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: panel.readSize = Math.max(12, Math.min(24, panel.readSize + parent.modelData.by)) }
                            ToolTip.visible: sizeHover.hovered
                            ToolTip.delay: 500
                            ToolTip.text: index === 0 ? qsTr("Smaller text (Ctrl+-)") : qsTr("Larger text (Ctrl+=)")
                        }
                    }
                    Text {
                        Layout.leftMargin: 8
                        Layout.rightMargin: 6
                        text: qsTr("%1 px").arg(panel.readSize)
                        color: Style.dim
                        font.family: Style.mono
                        font.variableAxes: Style.narrow
                        font.pixelSize: 10
                        font.features: { "tnum": 1 }
                    }
                }
                TacticalButton {
                    visible: !panel.failed && panel.path.length > 0
                    text: qsTr("Open in browser")
                    onClicked: ops.openReport(panel.path)
                }
            }
        }
    }
}
