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
        color: Qt.rgba(0, 0, 0, 0.8)
        // A MouseArea, unlike a TapHandler, stops the click here.
        MouseArea { anchors.fill: parent; onClicked: panel.close() }
    }

    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(820, parent.width - 48)
        height: Math.min(column.implicitHeight + 64, parent.height - 48)
        color: Qt.rgba(0.04, 0.05, 0.065, 0.97)
        border.color: Style.line
        radius: theme.radius
        // Clicks on the panel itself mustn't reach the dismissing backdrop.
        MouseArea { anchors.fill: parent }
        Rectangle { width: parent.width; height: 3; color: theme.accent }

        ParallelAnimation {
            id: enter
            NumberAnimation { target: sheet; property: "opacity"; from: 0; to: 1; duration: 160 }
            NumberAnimation { target: sheet; property: "scale"; from: 0.97; to: 1; duration: 220; easing.type: Easing.OutCubic }
        }

        ScrollView {
            anchors.fill: parent
            anchors.margins: 32
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                id: column
                width: parent.width
                spacing: 14

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: qsTr("Remote overwatch")
                        color: theme.accent
                        font.family: Style.mono
                        font.pixelSize: 11
                        font.letterSpacing: 4 * Style.tracking
                        font.capitalization: Font.AllUppercase
                    }
                    Text {
                        text: qsTr("Field terminal")
                        color: Style.text
                        font.family: Style.display
                        font.pixelSize: 30
                        font.weight: Font.Black
                        font.letterSpacing: 5 * Style.tracking
                        font.capitalization: Font.AllUppercase
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        text: qsTr("Check on operations from your phone: their comms and progress, answer questions, approve commands, send orders, hold or abort. Planning and deploying new work stays here.")
                        wrapMode: Text.Wrap
                        color: Style.dim
                        font.family: Style.display
                        font.pixelSize: 13
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Switch {
                        checked: terminal.enabled
                        onToggled: terminal.enabled = checked
                    }
                    Text {
                        Layout.fillWidth: true
                        text: !terminal.enabled ? qsTr("Off")
                            : terminal.listening ? qsTr("On · %n device(s) connected", "", terminal.clients)
                            : terminal.error
                        color: terminal.enabled && terminal.listening ? Style.good : terminal.enabled ? Style.danger : Style.dim
                        font.family: Style.display
                        font.pixelSize: 14
                        font.weight: Font.Bold
                        wrapMode: Text.Wrap
                    }
                    Text {
                        text: qsTr("Port")
                        color: Style.dim
                        font.family: Style.display
                        font.pixelSize: 12
                    }
                    TextField {
                        Layout.preferredWidth: 90
                        text: terminal.port
                        inputMethodHints: Qt.ImhDigitsOnly
                        validator: IntValidator { bottom: 1024; top: 65535 }
                        font.family: Style.mono
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
                            implicitHeight: choiceText.implicitHeight + 24
                            radius: theme.radius
                            color: chosen ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.12) : "transparent"
                            border.color: chosen ? theme.accent : Style.line
                            border.width: chosen ? 2 : 1
                            ColumnLayout {
                                id: choiceText
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 12
                                spacing: 3
                                Text {
                                    text: choice.modelData.title
                                    color: choice.chosen ? theme.accent : Style.text
                                    font.family: Style.display
                                    font.pixelSize: 14
                                    font.weight: Font.Black
                                    font.letterSpacing: 2 * Style.tracking
                                    font.capitalization: Font.AllUppercase
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: choice.modelData.body
                                    wrapMode: Text.Wrap
                                    color: Style.dim
                                    font.family: Style.display
                                    font.pixelSize: 12
                                }
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: terminal.lan = choice.modelData.lan }
                        }
                    }
                }

                // Pairing: the code carries the address and the token.
                RowLayout {
                    Layout.fillWidth: true
                    visible: terminal.listening
                    spacing: 20
                    Rectangle {
                        Layout.preferredWidth: 188
                        Layout.preferredHeight: 188
                        color: "white"
                        radius: Math.min(4, theme.radius)
                        Image {
                            anchors.fill: parent
                            anchors.margins: 6
                            source: terminal.pairingCode
                            visible: source.toString().length > 0
                            fillMode: Image.PreserveAspectFit
                            smooth: false
                        }
                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 20
                            visible: terminal.pairingCode.length === 0
                            text: qsTr("Install qrencode for a code to scan.")
                            wrapMode: Text.Wrap
                            horizontalAlignment: Text.AlignHCenter
                            color: "#333"
                            font.family: Style.display
                            font.pixelSize: 12
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        SectionLabel { Layout.fillWidth: true; text: qsTr("Pair a phone") }
                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Scan the code, or open this address. Keep it private: it's the key to your operations.")
                            wrapMode: Text.Wrap
                            color: Style.dim
                            font.family: Style.display
                            font.pixelSize: 12
                        }
                        TextField {
                            Layout.fillWidth: true
                            readOnly: true
                            text: terminal.pairingUrl
                            font.family: Style.mono
                            font.pixelSize: 11
                            onActiveFocusChanged: if (activeFocus) selectAll()
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: terminal.addresses.length > 1
                            text: qsTr("Also: %1").arg(terminal.addresses.slice(1).join("   "))
                            elide: Text.ElideRight
                            color: Style.faint
                            font.family: Style.mono
                            font.pixelSize: 11
                        }
                        TacticalButton {
                            text: qsTr("New code")
                            onClicked: terminal.newToken()
                        }
                        Text {
                            Layout.fillWidth: true
                            text: qsTr("A new code unpairs every device.")
                            color: Style.faint
                            font.family: Style.display
                            font.pixelSize: 11
                        }
                    }
                }

                SectionLabel { Layout.fillWidth: true; Layout.topMargin: 6; text: qsTr("Push alerts"); detail: qsTr("optional, via ntfy") }
                Text {
                    Layout.fillWidth: true
                    text: qsTr("Alerts (an agent waiting on you, a failure, a finished operation) can go to an ntfy topic, which the ntfy app shows as notifications. Use a hard-to-guess topic, or your own server.")
                    wrapMode: Text.Wrap
                    color: Style.dim
                    font.family: Style.display
                    font.pixelSize: 12
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    TextField {
                        id: ntfyField
                        Layout.fillWidth: true
                        placeholderText: qsTr("e.g. https://ntfy.sh/your-private-topic")
                        font.family: Style.mono
                        font.pixelSize: 12
                        onEditingFinished: terminal.ntfyUrl = text
                    }
                    TacticalButton {
                        text: qsTr("Send a test")
                        enabled: ntfyField.text.trim().length > 0
                        onClicked: { terminal.ntfyUrl = ntfyField.text; terminal.testPush() }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    TacticalButton { text: qsTr("Close"); key: "Esc"; onClicked: panel.close() }
                    Item { Layout.fillWidth: true }
                }
            }
        }
    }
}
