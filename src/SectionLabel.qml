import QtQuick

// A section's heading: a small square in the accent, the name in sentence
// case, a hairline to the right, and a figure at the end. The figure gives
// way (cut short) before the heading widens its column.
Item {
    id: label
    property string text
    property string detail
    implicitWidth: mark.width + name.implicitWidth + 40
    implicitHeight: Math.max(name.implicitHeight, 16)
    Rectangle {
        id: mark
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 5; height: 5
        color: theme.accent
    }
    Text {
        id: name
        anchors.left: mark.right
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, label.width - 15)
        elide: Text.ElideRight
        text: label.text
        color: Style.text2
        font.family: Style.body
        font.pixelSize: 13
        font.weight: Font.Medium
    }
    Text {
        id: figure
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, Math.max(0, label.width - name.x - name.width - 32))
        visible: label.detail.length > 0
        elide: Text.ElideRight
        text: label.detail
        color: Style.dim
        font.family: Style.mono
        font.variableAxes: Style.narrow
        font.pixelSize: 11
    }
    Rectangle {
        anchors.left: name.right
        anchors.leftMargin: 10
        anchors.right: figure.visible ? figure.left : parent.right
        anchors.rightMargin: figure.visible ? 10 : 0
        anchors.verticalCenter: parent.verticalCenter
        height: 1
        color: Style.line
    }
}
