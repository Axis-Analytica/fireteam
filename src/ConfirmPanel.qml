import QtQuick
import QtQuick.Layouts

// A yes-or-no question before anything is lost.
Item {
    id: confirm
    visible: false
    property string title
    property string body
    property string confirmText
    property var action: null

    function ask(t, b, c, f) {
        title = t; body = b; confirmText = c; action = f
        visible = true
    }
    function accept() {
        visible = false
        if (action) action()
        action = null
    }

    onVisibleChanged: if (visible) enter.restart()

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Style.bg.r, Style.bg.g, Style.bg.b, 0.86)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: confirm.visible = false }
    }
    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(500, parent.width - 48)
        height: column.implicitHeight
        color: Style.panel
        border.color: Style.lineStrong
        radius: theme.radius
        transform: Translate { id: lift }
        // Clicks on the panel itself mustn't reach the dismissing backdrop.
        MouseArea { anchors.fill: parent }
        Brackets { anchors.fill: parent; anchors.margins: -1; size: 12 }

        ParallelAnimation {
            id: enter
            NumberAnimation { target: sheet; property: "opacity"; from: 0; to: 1; duration: 140 }
            NumberAnimation { target: lift; property: "y"; from: 8; to: 0; duration: 180; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            id: column
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 0

            // Eyebrow: what's about to happen, as a comment, beside a square
            // in the colour of loss.
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 26
                Layout.leftMargin: 28
                Layout.rightMargin: 28
                spacing: 8
                Rectangle { implicitWidth: 6; implicitHeight: 6; color: Style.danger; Layout.alignment: Qt.AlignVCenter }
                Text {
                    Layout.fillWidth: true
                    text: "# " + confirm.confirmText.toLowerCase()
                    elide: Text.ElideRight
                    color: Style.dim
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 11
                }
            }
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.leftMargin: 28
                Layout.rightMargin: 28
                text: confirm.title
                wrapMode: Text.Wrap
                color: Style.text
                font.family: Style.display
                font.pixelSize: 26
                font.weight: Font.DemiBold
                font.letterSpacing: -0.6
            }
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 12
                Layout.bottomMargin: 24
                Layout.leftMargin: 28
                Layout.rightMargin: 28
                text: confirm.body
                wrapMode: Text.Wrap
                color: Style.text2
                lineHeight: 1.35
                font.family: Style.body
                font.pixelSize: 14
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 16
                Layout.leftMargin: 28
                spacing: 10
                Item { Layout.fillWidth: true }
                TacticalButton { text: qsTr("Cancel"); key: "Esc"; onClicked: confirm.visible = false }
                TacticalButton { text: confirm.confirmText; key: "Enter"; danger: true; onClicked: confirm.accept() }
            }
        }
    }
    Shortcut {
        enabled: confirm.visible
        sequences: ["Return", "Enter", "Y"]
        context: Qt.ApplicationShortcut
        onActivated: confirm.accept()
    }
}
