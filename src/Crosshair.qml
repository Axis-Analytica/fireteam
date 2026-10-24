import QtQuick

// A slowly turning reticle for empty states.
Item {
    implicitWidth: 120
    implicitHeight: 120
    Rectangle {
        anchors.centerIn: parent
        width: 96; height: 96; radius: 48
        color: "transparent"
        border.color: Qt.rgba(1, 1, 1, 0.18)
    }
    Item {
        anchors.fill: parent
        RotationAnimation on rotation { from: 0; to: 360; duration: 12000; loops: Animation.Infinite }
        Repeater {
            model: 4
            Rectangle {
                required property int index
                x: parent.width / 2 - 1
                y: 0
                width: 2; height: 22
                color: theme.accent
                transformOrigin: Item.Bottom
                transform: Rotation { origin.x: 1; origin.y: 60; angle: index * 90 }
            }
        }
    }
    Rectangle {
        anchors.centerIn: parent
        width: 6; height: 6; radius: 3
        color: theme.accent
        SequentialAnimation on opacity {
            loops: Animation.Infinite
            NumberAnimation { to: 0.2; duration: 700 }
            NumberAnimation { to: 1; duration: 700 }
        }
    }
}
