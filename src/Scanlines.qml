import QtQuick

// Fine CRT scanlines laid over the whole window.
Canvas {
    opacity: 0.5
    enabled: false
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        ctx.fillStyle = "rgba(0,0,0,0.22)"
        for (let y = 0; y < height; y += 3)
            ctx.fillRect(0, y, width, 1)
    }
}
