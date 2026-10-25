import QtQuick
import QtQuick.Layouts

// One row of an operation's comms: a time, a kind label and the line. The
// agent's own words read as prose (Markdown, code in mono); everything else
// stays narrow mono. A run of tool calls folds into one row that opens on a
// click to show each call.
RowLayout {
    id: line
    property string time
    property string kind
    property string text
    // More than one: a folded run of tool calls; entries holds them.
    property int count: 1
    property string summary
    property var entries: []
    property bool expanded: false
    signal toggled()

    readonly property bool folded: count > 1
    spacing: 10

    readonly property color tone: {
        switch (kind) {
        case "error": return Style.danger
        case "tool": return Style.text2
        case "result": return Style.good
        case "cmd": return Style.amber
        case "denied": return Style.amber
        case "review": return Style.good
        case "report": return theme.accent
        case "ask": return Style.danger
        case "sys": return Style.dim
        }
        return Style.text
    }

    // The agent writes Markdown; code spans and blocks are set in Martian
    // Mono, and a stray < is shown, not taken for a tag.
    function markdown(source) {
        const escape = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        const parts = source.split(/(```[\s\S]*?```|`[^`\n]+`)/)
        let out = ""
        for (let i = 0; i < parts.length; ++i) {
            const part = parts[i]
            if (i % 2 === 0)
                out += part.replace(/</g, "&lt;")
            else if (part.startsWith("```"))
                out += "\n\n<pre style=\"font-family: '" + Style.mono + "'; font-size: 11px;\">"
                     + escape(part.replace(/^```[^\n]*\n?/, "").replace(/\n?```$/, "")) + "</pre>\n\n"
            else
                out += "<span style=\"font-family: '" + Style.mono + "'; font-size: 12px;\">"
                     + escape(part.slice(1, -1)) + "</span>"
        }
        return out
    }

    Text {
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: line.kind === "say" ? 1 : 0
        text: line.time
        color: Style.faint
        font.family: Style.mono
        font.variableAxes: Style.narrow
        font.pixelSize: 11
    }
    Text {
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: line.kind === "say" ? 1 : 0
        Layout.preferredWidth: 52
        text: {
            switch (line.kind) {
            case "error": return qsTr("ERR")
            case "tool": return qsTr("ACT")
            case "result": return qsTr("SITREP")
            case "cmd": return qsTr("CMD")
            case "denied": return qsTr("BLOCK")
            case "review": return qsTr("REVIEW")
            case "report": return qsTr("REPORT")
            case "ask": return qsTr("ASK")
            case "sys": return qsTr("HQ")
            }
            return qsTr("AGENT")
        }
        color: line.kind === "say" ? theme.accent : line.kind === "tool" ? Style.dim : line.tone
        font.family: Style.mono
        font.variableAxes: Style.narrowMedium
        font.pixelSize: 11
    }

    // The agent's words.
    Text {
        Layout.fillWidth: true
        visible: line.kind === "say"
        text: visible ? line.markdown(line.text) : ""
        textFormat: Text.MarkdownText
        wrapMode: Text.Wrap
        color: Style.text2
        linkColor: theme.accent
        font.family: Style.body
        font.pixelSize: 13
        lineHeight: 1.25
        onLinkActivated: (link) => Qt.openUrlExternally(link)
        HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor; enabled: parent.hoveredLink.length > 0 }
    }

    // Anything else, one line or a folded run of tool calls.
    ColumnLayout {
        Layout.fillWidth: true
        visible: line.kind !== "say"
        spacing: 4
        Text {
            id: body
            Layout.fillWidth: true
            text: line.folded ? (line.expanded ? "▾ " : "▸ ") + qsTr("%1 actions").arg(line.count) + "  ·  " + line.summary
                              : line.text
            wrapMode: line.folded ? Text.NoWrap : Text.Wrap
            maximumLineCount: ["cmd", "review", "ask"].indexOf(line.kind) >= 0 ? 12 : 3
            elide: Text.ElideRight
            color: line.folded ? (foldHover.hovered ? Style.text : Style.text2) : line.tone
            font.family: Style.mono
            font.variableAxes: line.kind === "cmd" ? Style.narrowMedium : Style.narrow
            font.pixelSize: 12
            lineHeight: 1.15
            textFormat: Text.PlainText
            HoverHandler { id: foldHover; enabled: line.folded; cursorShape: Qt.PointingHandCursor }
            TapHandler { enabled: line.folded; onTapped: line.toggled() }
        }
        Repeater {
            model: line.folded && line.expanded ? line.entries : []
            delegate: RowLayout {
                id: step
                required property var modelData
                Layout.fillWidth: true
                Layout.leftMargin: 14
                spacing: 10
                Text {
                    Layout.alignment: Qt.AlignTop
                    text: step.modelData.time
                    color: Style.faint
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 11
                }
                Text {
                    Layout.fillWidth: true
                    text: step.modelData.text
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    color: Style.text2
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 12
                    textFormat: Text.PlainText
                }
            }
        }
    }
}
