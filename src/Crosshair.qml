import QtQuick

// A still reticle for empty states: corner marks, hairs at the edges, and a
// square at the centre where nothing is yet.
Item {
    id: reticle
    implicitWidth: 120
    implicitHeight: 120

    Item {
        id: frame
        anchors.centerIn: parent
        width: 88
        height: 88
        Brackets {
            anchors.fill: parent
            color: Style.lineStrong
            size: 14
        }
        // Hairs from each edge toward the centre.
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: 0; width: 1; height: 18; color: theme.accent }
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: parent.height - height; width: 1; height: 18; color: theme.accent }
        Rectangle { anchors.verticalCenter: parent.verticalCenter; x: 0; width: 18; height: 1; color: theme.accent }
        Rectangle { anchors.verticalCenter: parent.verticalCenter; x: parent.width - width; width: 18; height: 1; color: theme.accent }
        Rectangle {
            anchors.centerIn: parent
            width: 5
            height: 5
            color: theme.accent
        }
    }
}
