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

    Rectangle {
        anchors.fill: parent
        color: hover.hovered ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.4)
        border.color: card.current ? card.tone : Style.line
        radius: Math.min(4, theme.radius)
    }
    Rectangle { width: 3; height: parent.height; color: card.tone }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 10
        anchors.topMargin: 8
        anchors.bottomMargin: 8
        spacing: 1
        RowLayout {
            spacing: 8
            Text {
                text: qsTr("C%1").arg(Style.pad(card.modelData.cycle))
                color: Style.text
                font.family: Style.display
                font.pixelSize: 16
                font.weight: Font.Black
                font.letterSpacing: 2
            }
            Text {
                Layout.fillWidth: true
                text: card.outcome === "complete" ? qsTr("S%1").arg(card.modelData.session)
                    : card.outcome === "cut" ? qsTr("Cut short")
                    : card.outcome === "aborted" ? qsTr("Aborted") : qsTr("Failed")
                horizontalAlignment: Text.AlignRight
                color: card.outcome === "complete" ? Style.dim : card.tone
                font.family: Style.mono
                font.pixelSize: 10
                font.bold: true
                font.capitalization: Font.AllUppercase
            }
        }
        Text {
            text: card.modelData.before ? qsTr("%1 files · <font color=\"%2\">+%3</font> <font color=\"%4\">−%5</font>")
                                              .arg(card.modelData.files).arg(Style.good).arg(card.modelData.added)
                                              .arg(Style.danger).arg(card.modelData.removed)
                                        : qsTr("No git intel")
            textFormat: Text.StyledText
            color: Style.text
            font.family: Style.mono
            font.pixelSize: 11
        }
        Text {
            text: qsTr("%1 · ≈$%2").arg(card.duration(card.modelData.seconds))
                      .arg(Number(card.modelData.cost).toLocaleString(Qt.locale(), 'f', 2))
            color: Style.dim
            font.family: Style.mono
            font.pixelSize: 10
        }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: card.opened() }
}
