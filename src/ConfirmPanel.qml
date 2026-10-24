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

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.8)
        TapHandler { onTapped: confirm.visible = false }
    }
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(520, parent.width - 48)
        height: column.implicitHeight + 56
        color: Qt.rgba(0.04, 0.05, 0.065, 0.97)
        border.color: Style.line
        radius: theme.radius
        TapHandler {}
        Rectangle { width: parent.width; height: 3; color: Style.danger }
        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: 28
            spacing: 14
            Text {
                Layout.fillWidth: true
                text: confirm.title
                wrapMode: Text.Wrap
                color: Style.text
                font.family: Style.display
                font.pixelSize: 24
                font.weight: Font.Black
                font.letterSpacing: 4
                font.capitalization: Font.AllUppercase
            }
            Text {
                Layout.fillWidth: true
                text: confirm.body
                wrapMode: Text.Wrap
                color: Style.dim
                font.family: Style.display
                font.pixelSize: 14
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                TacticalButton { text: qsTr("Cancel"); key: "Esc"; onClicked: confirm.visible = false }
                Item { Layout.fillWidth: true }
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
