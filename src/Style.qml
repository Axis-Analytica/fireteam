pragma Singleton
import QtQuick

QtObject {
    // The ground and ink follow the Omarchy accent's hue (see Theme): a near-
    // black ground in three lightness steps, pale ink, one signal colour.
    readonly property color bg: theme.paper
    readonly property color panel: theme.paper2
    readonly property color raised: theme.paper3
    readonly property color line: theme.rule
    readonly property color lineStrong: theme.rule2
    readonly property color text: theme.ink
    readonly property color text2: theme.ink2
    readonly property color dim: theme.muted
    readonly property color faint: theme.faint
    readonly property color wash: theme.wash
    // States, kept few and quiet beside the accent.
    readonly property color danger: "#f0605a"
    readonly property color good: "#7ccf8a"
    readonly property color amber: "#e6b85c"

    // Martian Mono for callsigns, figures and anything typed; Red Hat for
    // reading. Wide heads, narrow text.
    readonly property string mono: "Martian Mono"
    readonly property string display: "Red Hat Display"
    readonly property string body: "Red Hat Text"
    // Martian Mono's width and weight are axes of one variable font, and Qt
    // sets them through variableAxes (font.weight alone doesn't move them).
    readonly property var wide: ({ "wdth": 112.5, "wght": 500 })
    readonly property var figure: ({ "wdth": 112.5, "wght": 300 })
    readonly property var narrow: ({ "wdth": 87.5, "wght": 400 })
    readonly property var narrowMedium: ({ "wdth": 87.5, "wght": 560 })

    // Letter-spacing for the few tracked labels left, off for right-to-left
    // scripts, whose joined letters it would pull apart.
    readonly property real tracking: Qt.application.layoutDirection === Qt.RightToLeft ? 0 : 1

    function statusColor(status, accent) {
        switch (status) {
        case "deployed": return accent
        case "complete": return good
        case "failed":
        case "aborted": return danger
        case "interrupted":
        case "held":
        case "pinned": return amber
        case "staged":
        case "scheduled": return Qt.lighter(dim, 1.3)
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
        case "scheduled": return qsTr("Scheduled")
        }
        return qsTr("Standby")
    }

    function gradeColor(grade) {
        return grade === "pass" ? good : grade === "needs-work" ? amber : grade === "fail" ? danger : dim
    }
    function gradeLabel(grade) {
        return grade === "pass" ? qsTr("Pass") : grade === "needs-work" ? qsTr("Needs work")
             : grade === "fail" ? qsTr("Fail") : qsTr("No verdict")
    }

    function tokens(n) {
        if (n >= 1000000) return (n / 1000000).toLocaleString(Qt.locale(), 'f', n % 1000000 ? 1 : 0) + "M"
        if (n >= 1000) return Math.round(n / 1000) + "k"
        return "" + Math.round(n)
    }

    function pad(n) { return n < 10 ? "0" + n : "" + n }
}
