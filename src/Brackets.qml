import QtQuick

// Corner marks around whatever it fills, like a reticle settling on a target.
Item {
    id: brackets
    property color color: theme.accent
    property int size: 8
    property int weight: 1
    enabled: false
    Repeater {
        model: 4
        Item {
            required property int index
            readonly property bool atRight: index % 2 === 1
            readonly property bool atBottom: index > 1
            x: atRight ? brackets.width - brackets.size : 0
            y: atBottom ? brackets.height - brackets.size : 0
            width: brackets.size
            height: brackets.size
            Rectangle { y: parent.atBottom ? parent.height - height : 0; width: parent.width; height: brackets.weight; color: brackets.color }
            Rectangle { x: parent.atRight ? parent.width - width : 0; width: brackets.weight; height: parent.height; color: brackets.color }
        }
    }
}
