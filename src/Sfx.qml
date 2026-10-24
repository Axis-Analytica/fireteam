pragma Singleton
import QtCore
import QtQuick
import QtMultimedia

// Interface sounds, off until switched on with Shift+M. The choice is kept in
// ~/.config/fireteam/settings.ini.
QtObject {
    id: sfx
    property bool enabled: store.sound

    function toggle() {
        store.sound = !store.sound
        if (store.sound)
            play("select")
    }
    function play(name) {
        if (!enabled)
            return
        const effect = effects[name]
        if (effect)
            effect.play()
    }

    property Settings store: Settings {
        location: StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/fireteam/settings.ini"
        category: "sound"
        property bool sound: false
    }

    readonly property var effects: ({ tick: tick, select: select, open: open, deploy: deploy,
                                      done: done, complete: complete, fail: fail })
    property SoundEffect tick: SoundEffect { source: "qrc:/sounds/tick.wav"; volume: 0.35 }
    property SoundEffect select: SoundEffect { source: "qrc:/sounds/select.wav"; volume: 0.5 }
    property SoundEffect open: SoundEffect { source: "qrc:/sounds/open.wav"; volume: 0.5 }
    property SoundEffect deploy: SoundEffect { source: "qrc:/sounds/deploy.wav"; volume: 0.6 }
    property SoundEffect done: SoundEffect { source: "qrc:/sounds/done.wav"; volume: 0.55 }
    property SoundEffect complete: SoundEffect { source: "qrc:/sounds/complete.wav"; volume: 0.6 }
    property SoundEffect fail: SoundEffect { source: "qrc:/sounds/fail.wav"; volume: 0.55 }
}
