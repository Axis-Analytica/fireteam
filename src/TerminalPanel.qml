import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// The field terminal's switch and pairing: where to reach it from a phone,
// the code to scan, and where alerts are pushed.
Item {
    id: panel
    visible: false

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius

    function open() {
        ntfyField.text = terminal.ntfyUrl
        visible = true
        enter.restart()
    }
    function close() {
        terminal.ntfyUrl = ntfyField.text
        visible = false
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Style.bg.r, Style.bg.g, Style.bg.b, 0.86)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: panel.close() }
    }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(820, parent.width - 48)
        height: Math.min(head.implicitHeight + column.implicitHeight + foot.implicitHeight + 2 + 28 + 20 + 40 + 32,
                         parent.height - 48)
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
            anchors.fill: parent
            spacing: 0

            ColumnLayout {
                id: head
                Layout.fillWidth: true
                Layout.margins: 32
                Layout.topMargin: 28
                Layout.bottomMargin: 20
                spacing: 4
                Text {
                    Layout.fillWidth: true
                    text: "# " + qsTr("Remote overwatch")
                    elide: Text.ElideRight
                    color: Style.dim
                    font.family: Style.mono
                    font.variableAxes: Style.narrow
                    font.pixelSize: 11
                }
                Text {
                    Layout.fillWidth: true
                    text: qsTr("Field terminal")
                    elide: Text.ElideRight
                    color: Style.text
                    font.family: Style.display
                    font.pixelSize: 28
                    font.weight: Font.DemiBold
                    font.letterSpacing: -0.6
                }
                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    text: qsTr("Check on operations from your phone: their comms and progress, answer questions, approve commands, send orders, hold or abort. Planning and deploying new work stays here.")
                    wrapMode: Text.Wrap
                    color: Style.text2
                    font.family: Style.body
                    font.pixelSize: 13
                    lineHeight: 1.15
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }

            ScrollView {
                id: scroller
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 32
                Layout.rightMargin: 32
                Layout.topMargin: 20
                Layout.bottomMargin: 20
                contentWidth: availableWidth
                clip: true

                ColumnLayout {
                    id: column
                    width: scroller.availableWidth
                    spacing: 14

                    // The switch, its state as a status square, and the port.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Switch {
                            Layout.leftMargin: -6
                            checked: terminal.enabled
                            onToggled: terminal.enabled = checked
                        }
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: 7; implicitHeight: 7
                            color: terminal.enabled && terminal.listening ? Style.good : terminal.enabled ? Style.danger : Style.faint
                        }
                        Text {
                            Layout.fillWidth: true
                            text: !terminal.enabled ? qsTr("Off")
                                : terminal.listening ? qsTr("On · %n device(s) connected", "", terminal.clients)
                                : terminal.error
                            color: terminal.enabled && !terminal.listening ? Style.danger : Style.text2
                            font.family: Style.body
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            wrapMode: Text.Wrap
                        }
                        Text {
                            text: qsTr("Port")
                            color: Style.dim
                            font.family: Style.body
                            font.pixelSize: 12
                        }
                        TextField {
                            Layout.preferredWidth: 96
                            text: terminal.port
                            inputMethodHints: Qt.ImhDigitsOnly
                            validator: IntValidator { bottom: 1024; top: 65535 }
                            font.family: Style.mono
                            font.variableAxes: Style.narrow
                            font.pixelSize: 13
                            onEditingFinished: terminal.port = parseInt(text)
                        }
                    }

                    // Where it listens: this machine, or the local network.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Repeater {
                            model: [
                                { lan: false, title: qsTr("This machine only"), body: qsTr("Reachable at 127.0.0.1, or through your own tunnel.") },
                                { lan: true, title: qsTr("Local network"), body: qsTr("Any device on your network or Tailscale that has the code. Plain HTTP: use it on networks you trust.") }
                            ]
                            delegate: Rectangle {
                                id: choice
                                required property var modelData
                                readonly property bool chosen: terminal.lan === modelData.lan
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.preferredWidth: 1
                                implicitHeight: choiceText.implicitHeight + 28
                                radius: Math.min(2, theme.radius)
                                color: chosen ? Style.wash : choiceHover.hovered ? Style.raised : Style.bg
                                border.color: chosen ? Style.lineStrong : Style.line
                                Rectangle { visible: choice.chosen; width: 2; height: parent.height; color: theme.accent }
                                ColumnLayout {
                                    id: choiceText
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 14
                                    anchors.leftMargin: 16
                                    spacing: 4
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        // A radio mark: filled when this is the choice.
                                        Rectangle {
                                            implicitWidth: 10; implicitHeight: 10
                                            Layout.alignment: Qt.AlignVCenter
                                            color: "transparent"
                                            border.color: choice.chosen ? theme.accent : Style.dim
                                            Rectangle { anchors.centerIn: parent; width: 4; height: 4; visible: choice.chosen; color: theme.accent }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: choice.modelData.title
                                            elide: Text.ElideRight
                                            color: Style.text
                                            font.family: Style.body
                                            font.pixelSize: 14
                                            font.weight: Font.Medium
                                        }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 18
                                        text: choice.modelData.body
                                        wrapMode: Text.Wrap
                                        color: Style.dim
                                        font.family: Style.body
                                        font.pixelSize: 12
                                    }
                                }
                                HoverHandler { id: choiceHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: terminal.lan = choice.modelData.lan }
                            }
                        }
                    }

                    // Pairing: the code carries the address and the token.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        visible: terminal.listening
                        spacing: 24
                        Rectangle {
                            Layout.alignment: Qt.AlignTop
                            Layout.leftMargin: 6
                            Layout.topMargin: 6
                            Layout.preferredWidth: 176
                            Layout.preferredHeight: 176
                            // A code to scan wants a light ground, whatever the theme.
                            color: "white"
                            border.color: Style.lineStrong
                            radius: Math.min(2, theme.radius)
                            Image {
                                anchors.fill: parent
                                anchors.margins: 8
                                source: terminal.pairingCode
                                visible: source.toString().length > 0
                                fillMode: Image.PreserveAspectFit
                                smooth: false
                            }
                            Text {
                                anchors.centerIn: parent
                                width: parent.width - 24
                                visible: terminal.pairingCode.length === 0
                                text: qsTr("Install qrencode for a code to scan.")
                                wrapMode: Text.Wrap
                                horizontalAlignment: Text.AlignHCenter
                                color: Style.bg
                                font.family: Style.body
                                font.pixelSize: 12
                            }
                            Brackets { anchors.fill: parent; anchors.margins: -5; size: 10 }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: 10
                            SectionLabel { Layout.fillWidth: true; text: qsTr("Pair a phone") }
                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Scan the code, or open this address. Keep it private: it's the key to your operations.")
                                wrapMode: Text.Wrap
                                color: Style.text2
                                font.family: Style.body
                                font.pixelSize: 13
                            }
                            TextField {
                                Layout.fillWidth: true
                                readOnly: true
                                text: terminal.pairingUrl
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 11
                                onActiveFocusChanged: if (activeFocus) selectAll()
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: terminal.addresses.length > 1
                                text: qsTr("Also: %1").arg(terminal.addresses.slice(1).join("   "))
                                elide: Text.ElideRight
                                color: Style.dim
                                font.family: Style.mono
                                font.variableAxes: Style.narrow
                                font.pixelSize: 11
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12
                                TacticalButton {
                                    text: qsTr("New code")
                                    onClicked: terminal.newToken()
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: qsTr("A new code unpairs every device.")
                                    wrapMode: Text.Wrap
                                    color: Style.dim
                                    font.family: Style.body
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }

                    SectionLabel { Layout.fillWidth: true; Layout.topMargin: 10; text: qsTr("Push alerts"); detail: qsTr("optional, via ntfy") }
                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Alerts (an agent waiting on you, a failure, a finished operation) can go to an ntfy topic, which the ntfy app shows as notifications. Use a hard-to-guess topic, or your own server.")
                        wrapMode: Text.Wrap
                        color: Style.text2
                        font.family: Style.body
                        font.pixelSize: 13
                        lineHeight: 1.15
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        TextField {
                            id: ntfyField
                            Layout.fillWidth: true
                            placeholderText: qsTr("e.g. https://ntfy.sh/your-private-topic")
                            font.family: Style.mono
                            font.variableAxes: Style.narrow
                            font.pixelSize: 12
                            onEditingFinished: terminal.ntfyUrl = text
                        }
                        TacticalButton {
                            text: qsTr("Send a test")
                            enabled: ntfyField.text.trim().length > 0
                            onClicked: { terminal.ntfyUrl = ntfyField.text; terminal.testPush() }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.line }

            RowLayout {
                id: foot
                Layout.fillWidth: true
                Layout.leftMargin: 32
                Layout.rightMargin: 32
                Layout.topMargin: 16
                Layout.bottomMargin: 16
                spacing: 10
                TacticalButton { text: qsTr("Close"); key: "Esc"; onClicked: panel.close() }
                Item { Layout.fillWidth: true }
            }
        }
    }
}
