pragma Singleton
import QtCore
import QtQuick

// The board's own preferences, beside the sound switch in
// ~/.config/fireteam/settings.ini. What operations run with lives in the data
// directory's settings.json instead (Operations).
Settings {
    location: StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/fireteam/settings.ini"
    category: "board"
    // The insertion screen when an operation deploys.
    property bool insertion: true
    // Dust and embers drifting behind the board.
    property bool motion: true
    // The loadout a new briefing starts from; empty for none.
    property string defaultLoadout: ""
    // The knowledge graph in three dimensions, turning slowly when left alone.
    property bool graph3d: false
    property bool graphSpin: true
}
