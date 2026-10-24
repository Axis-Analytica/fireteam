pragma Singleton
import QtQuick

QtObject {
    readonly property color bg: "#05070a"
    readonly property color panel: "#0b0e12"
    readonly property color line: "#1d2329"
    readonly property color text: "#ebe9e4"
    readonly property color dim: "#858b91"
    readonly property color faint: "#3b4248"
    readonly property color danger: "#ff4f45"
    readonly property color good: "#86e07d"
    readonly property color amber: "#e9b44c"

    readonly property string display: "Adwaita Sans"
    readonly property string mono: "GeistMono Nerd Font"

    function statusColor(status, accent) {
        switch (status) {
        case "deployed": return accent
        case "complete": return good
        case "failed":
        case "aborted": return danger
        case "interrupted": return amber
        }
        return dim
    }

    function statusLabel(status) {
        switch (status) {
        case "deployed": return qsTr("Deployed")
        case "complete": return qsTr("Complete")
        case "failed": return qsTr("Failed")
        case "aborted": return qsTr("Aborted")
        case "interrupted": return qsTr("Interrupted")
        }
        return qsTr("Standby")
    }

    function pad(n) { return n < 10 ? "0" + n : "" + n }
}
