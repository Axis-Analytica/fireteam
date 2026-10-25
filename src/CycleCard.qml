import QtQuick
import QtQuick.Layouts

// One cycle run in the timeline: how it ended, what it changed, and what it
// took. Clicking it opens the cycle's diff.
Item {
    id: card
    required property var modelData
    required property int index
    property bool current: false
    signal opened()

    readonly property string outcome: modelData.outcome
    readonly property color tone: outcome === "complete" ? theme.accent
                                : outcome === "cut" ? Style.amber
                                : Style.danger

    function duration(seconds) {
        if (seconds < 60) return seconds + "s"
        if (seconds < 3600) return Math.floor(seconds / 60) + "m " + Style.pad(seconds % 60) + "s"
        return Math.floor(seconds / 3600) + "h " + Style.pad(Math.floor(seconds % 3600 / 60)) + "m"
    }

    implicitWidth: 176
    implicitHeight: 64

    // The latest cycle is selected: a wash of the accent, a rule down the
    // leading edge and corner marks. Hover lifts the card a step, at once.
    Rectangle {
        anchors.fill: parent
        color: card.current ? Style.wash : hover.hovered ? Style.raised : Style.panel
        border.color: card.current ? "transparent" : Style.line
        radius: Math.min(2, theme.radius)
    }
    Rectangle {
        visible: card.current
        width: 2
        height: parent.height
        color: theme.accent
    }
    Brackets {
        anchors.fill: parent
        visible: card.current
        size: 7
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 10
        anchors.topMargin: 8
        anchors.bottomMargin: 8
        spacing: 2
        RowLayout {
            spacing: 7
            // How the cycle ended, as a square in its state's colour.
            Rectangle {
                implicitWidth: 6
                implicitHeight: 6
                Layout.alignment: Qt.AlignVCenter
                color: card.tone
            }
            Text {
                text: qsTr("C%1").arg(Style.pad(card.modelData.cycle))
                color: card.current ? Style.text : Style.text2
                font.family: Style.mono
                font.variableAxes: Style.wide
                font.pixelSize: 14
                font.letterSpacing: -0.3
                font.features: { "tnum": 1 }
            }
            // One square per gate, passed or failed; a camera when there's a screenshot.
            Row {
                spacing: 2
                Layout.alignment: Qt.AlignVCenter
                visible: card.modelData.gates !== undefined
                Repeater {
                    model: card.modelData.gates || []
                    delegate: Rectangle {
                        required property var modelData
                        width: 5; height: 5
                        color: modelData.passed ? Style.good : Style.danger
                    }
                }
            }
            Text {
                visible: card.modelData.screenshot !== undefined
                text: "◫"
                color: Style.dim
                font.family: Style.mono
                font.pixelSize: 10
            }
            Text {
                Layout.fillWidth: true
                text: card.outcome === "complete" ? qsTr("S%1").arg(card.modelData.session)
                    : card.outcome === "cut" ? qsTr("Cut short")
                    : card.outcome === "aborted" ? qsTr("Aborted") : qsTr("Failed")
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                color: card.outcome === "complete" ? Style.dim : card.tone
                font.family: card.outcome === "complete" ? Style.mono : Style.body
                font.variableAxes: Style.narrow
                font.pixelSize: card.outcome === "complete" ? 10 : 11
                font.weight: card.outcome === "complete" ? Font.Normal : Font.Medium
            }
        }
        Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: card.modelData.before ? qsTr("%n file(s)", "", card.modelData.files)
                                          + qsTr(" · <font color=\"%1\">+%2</font> <font color=\"%3\">−%4</font>")
                                              .arg(theme.accent).arg(card.modelData.added)
                                              .arg(Style.dim).arg(card.modelData.removed)
                                        : qsTr("No git intel")
            textFormat: Text.StyledText
            color: Style.text2
            font.family: Style.mono
            font.variableAxes: Style.narrow
            font.pixelSize: 11
            font.features: { "tnum": 1 }
        }
        Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: qsTr("%1 · ≈$%2").arg(card.duration(card.modelData.seconds))
                      .arg(Number(card.modelData.cost).toLocaleString(Qt.locale(), 'f', 2))
            color: Style.dim
            font.family: Style.mono
            font.variableAxes: Style.narrow
            font.pixelSize: 10
            font.features: { "tnum": 1 }
        }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: card.opened() }
}
