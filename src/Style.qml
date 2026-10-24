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
        case "interrupted":
        case "held":
        case "pinned": return amber
        case "staged": return Qt.lighter(dim, 1.3)
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
        case "held": return qsTr("Holding")
        case "staged": return qsTr("Staged")
        case "pinned": return qsTr("Pinned down")
        }
        return qsTr("Standby")
    }

    function tokens(n) {
        if (n >= 1000000) return (n / 1000000).toLocaleString(Qt.locale(), 'f', n % 1000000 ? 1 : 0) + "M"
        if (n >= 1000) return Math.round(n / 1000) + "k"
        return "" + Math.round(n)
    }

    function pad(n) { return n < 10 ? "0" + n : "" + n }
}
