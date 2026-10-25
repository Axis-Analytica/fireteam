import QtQuick

// A small oscilloscope of how busy an agent is: each bar is how many lines of
// comms (speech and tool calls) arrived in a quarter second.
Item {
    id: pulse
    property int events: 0
    property bool live: false
    property color tone: theme.accent
    property int bars: 36

    property var samples: []
    property int seen: -1

    implicitWidth: 72
    implicitHeight: 18

    Timer {
        interval: 250
        repeat: true
        running: pulse.live && pulse.visible
        onTriggered: {
            const delta = pulse.seen < 0 ? 0 : Math.max(0, pulse.events - pulse.seen)
            pulse.seen = pulse.events
            const next = pulse.samples.concat([delta])
            pulse.samples = next.length > pulse.bars ? next.slice(next.length - pulse.bars) : next
            scope.requestPaint()
        }
    }
    onLiveChanged: if (!live) { samples = []; seen = -1; scope.requestPaint() }

    Canvas {
        id: scope
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const step = width / pulse.bars
            const mid = height / 2
            // A flat trace when idle, so the gauge still reads as a gauge.
            ctx.strokeStyle = Style.line
            ctx.lineWidth = 1
            ctx.beginPath(); ctx.moveTo(0, mid + .5); ctx.lineTo(width, mid + .5); ctx.stroke()
            ctx.fillStyle = pulse.tone
            const offset = pulse.bars - pulse.samples.length
            for (let i = 0; i < pulse.samples.length; ++i) {
                const v = Math.min(1, pulse.samples[i] / 4)
                if (v <= 0) continue
                const h = Math.max(2, v * height)
                ctx.globalAlpha = 0.35 + 0.65 * (i / pulse.samples.length)
                ctx.fillRect((offset + i) * step, mid - h / 2, Math.max(1, step - 1), h)
            }
        }
    }
}
