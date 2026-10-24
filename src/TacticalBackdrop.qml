import QtQuick
import QtQuick.Particles

// The living background: drifting dust, rising embers in the accent, slow
// out-of-focus bokeh, faint topographic contours, and a sweep line.
Item {
    id: root
    property color accent: "#FFD60A"
    property bool active: true

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#0a0d11" }
            GradientStop { position: 0.55; color: Style.bg }
            GradientStop { position: 1; color: "#020304" }
        }
    }

    // Contours and a coordinate grid, drawn once per size.
    Canvas {
        id: map
        anchors.fill: parent
        opacity: 0.55
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.strokeStyle = "rgba(255,255,255,0.035)"
            ctx.lineWidth = 1
            for (let x = 0; x < width; x += 64) { ctx.beginPath(); ctx.moveTo(x + .5, 0); ctx.lineTo(x + .5, height); ctx.stroke() }
            for (let y = 0; y < height; y += 64) { ctx.beginPath(); ctx.moveTo(0, y + .5); ctx.lineTo(width, y + .5); ctx.stroke() }
            const cx = width * 0.78, cy = height * 0.42
            for (let ring = 1; ring < 16; ++ring) {
                ctx.beginPath()
                for (let a = 0; a <= 360; a += 4) {
                    const t = a * Math.PI / 180
                    const wobble = 1 + 0.12 * Math.sin(3 * t + ring * 0.7) + 0.06 * Math.sin(7 * t - ring)
                    const r = ring * 42 * wobble
                    const px = cx + Math.cos(t) * r * 1.35, py = cy + Math.sin(t) * r
                    if (a === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py)
                }
                ctx.strokeStyle = ring % 5 === 0 ? "rgba(255,255,255,0.07)" : "rgba(255,255,255,0.03)"
                ctx.stroke()
            }
        }
    }

    ParticleSystem {
        id: particles
        anchors.fill: parent
        running: root.active
    }

    ImageParticle {
        system: particles
        groups: ["bokeh"]
        source: "qrc:/ember.svg"
        color: root.accent
        alpha: 0.05
        alphaVariation: 0.04
        entryEffect: ImageParticle.Fade
    }
    ImageParticle {
        system: particles
        groups: ["dust"]
        source: "qrc:/ember.svg"
        color: "#d8d4cc"
        alpha: 0.35
        alphaVariation: 0.25
        entryEffect: ImageParticle.Fade
    }
    ImageParticle {
        system: particles
        groups: ["embers"]
        source: "qrc:/ember.svg"
        color: root.accent
        colorVariation: 0.08
        alpha: 0.9
        alphaVariation: 0.4
        entryEffect: ImageParticle.Fade
    }

    Emitter {
        system: particles
        group: "bokeh"
        anchors.fill: parent
        emitRate: 1.2
        lifeSpan: 16000
        lifeSpanVariation: 4000
        size: 140
        sizeVariation: 90
        endSize: 200
        velocity: AngleDirection { angle: 280; angleVariation: 40; magnitude: 8; magnitudeVariation: 6 }
    }
    Emitter {
        system: particles
        group: "dust"
        anchors.fill: parent
        emitRate: 36
        lifeSpan: 9000
        lifeSpanVariation: 3000
        size: 3
        sizeVariation: 2.5
        velocity: AngleDirection { angle: 300; angleVariation: 50; magnitude: 14; magnitudeVariation: 10 }
    }
    Emitter {
        system: particles
        group: "embers"
        width: parent.width
        height: 20
        anchors.bottom: parent.bottom
        emitRate: 14
        lifeSpan: 6500
        lifeSpanVariation: 2500
        size: 5
        sizeVariation: 4
        endSize: 1
        velocity: AngleDirection { angle: 275; angleVariation: 22; magnitude: 70; magnitudeVariation: 45 }
        acceleration: AngleDirection { angle: 270; magnitude: 6 }
    }
    Wander {
        system: particles
        groups: ["dust", "embers"]
        anchors.fill: parent
        xVariance: 40
        pace: 60
    }
    Turbulence {
        system: particles
        groups: ["embers"]
        anchors.fill: parent
        strength: 28
    }

    // A slow scan band rolling down the screen.
    Rectangle {
        id: sweep
        width: parent.width
        height: 140
        opacity: 0.07
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.92; color: root.accent }
            GradientStop { position: 1; color: "transparent" }
        }
        NumberAnimation on y {
            from: -sweep.height; to: root.height
            duration: 9000; loops: Animation.Infinite; running: root.active
        }
    }

    // Vignette and scanlines over everything.
    Canvas {
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const g = ctx.createRadialGradient(width / 2, height / 2, Math.min(width, height) * 0.35,
                                               width / 2, height / 2, Math.max(width, height) * 0.75)
            g.addColorStop(0, "rgba(0,0,0,0)")
            g.addColorStop(1, "rgba(0,0,0,0.75)")
            ctx.fillStyle = g
            ctx.fillRect(0, 0, width, height)
        }
    }
}
