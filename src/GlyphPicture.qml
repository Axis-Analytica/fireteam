import QtQuick

// A picture printed in characters: a survey of invented ground, drawn from a
// seed (the same seed always prints the same picture). Its brightness is a
// field of layered noise read as terrain: contour lines, a few ridgelines, a
// coastline around an organic silhouette and a cross on the summit, cut into
// eight levels. Each lit cell is the next character of `source`, coloured on a
// ramp of the accent from dark to bright; dim cells print smaller. It resolves
// row by row from noise the first time it's shown, and cells under the cursor
// flare to the accent, then settle.
Item {
    id: picture
    property string seed: ""
    property string source: "FIRETEAM"
    property int columns: 96
    // Cells are 1.85 times as tall as wide, so this many rows prints a picture
    // a little under twice as wide as tall.
    property int rows: Math.max(4, Math.round(columns * 0.3))
    // The glyph size the implicit size comes from; set a width (or height)
    // instead and the cells fit it.
    property real fontSize: 9
    property bool resolve: true
    // Dim cells print at this share of a full cell.
    property real dimScale: 0.62
    readonly property bool resolving: resolveClock.running

    // theme.accent is a name ("#ffd60a"); as a colour its channels can be read.
    readonly property color accent: theme.accent
    readonly property color ground: Style.bg

    readonly property real cellAspect: 1.85
    implicitWidth: Math.round(columns * fontSize * metrics.ratio)
    implicitHeight: Math.round(rows * fontSize * metrics.ratio * cellAspect)

    // Prints it again from noise (the insertion screen does, each time it plays).
    function replay() {
        resolved = false
        if (visible) begin()
    }

    // ── internals ──────────────────────────────────────────────────────────
    property bool resolved: false
    property real progress: 1
    property var levels: []
    property var chars: []
    property var byLevel: []
    property var flares: ({})
    property var ramp: []
    property var rampColours: []
    property color flareInk: accent

    // The canvas draws Martian Mono at its default width; its advance sets
    // how large a glyph fills a cell.
    FontMetrics {
        id: metrics
        font.family: Style.mono
        font.pixelSize: 100
        readonly property real ratio: Math.max(0.4, advanceWidth("0") / 100)
    }

    function begin() {
        if (resolved) return
        resolved = true
        if (!resolve || Prefs.reduceMotion) {
            progress = 1
            canvas.requestPaint()
            return
        }
        progress = 0
        resolveClock.started = Date.now()
        resolveClock.restart()
    }
    onVisibleChanged: if (visible) begin()
    Component.onCompleted: { build(); colours(); if (visible) begin() }
    onSeedChanged: build()
    onSourceChanged: build()
    onColumnsChanged: build()
    onRowsChanged: build()
    onAccentChanged: colours()
    onGroundChanged: colours()

    function hashString(s) {
        let h = 2166136261 >>> 0
        for (let i = 0; i < s.length; ++i) {
            h ^= s.charCodeAt(i)
            h = Math.imul(h, 16777619) >>> 0
        }
        return h
    }
    function generator(a) {
        return function() {
            a = (a + 0x6D2B79F5) | 0
            let t = Math.imul(a ^ (a >>> 15), 1 | a)
            t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
            return ((t ^ (t >>> 14)) >>> 0) / 4294967296
        }
    }
    // Smooth value noise on a shuffled lattice, and octaves of it.
    function valueNoise(rand) {
        const perm = [], values = []
        for (let i = 0; i < 256; ++i) { perm.push(i); values.push(rand()) }
        for (let i = 255; i > 0; --i) {
            const j = Math.floor(rand() * (i + 1)), t = perm[i]
            perm[i] = perm[j]; perm[j] = t
        }
        for (let i = 0; i < 256; ++i) perm.push(perm[i])
        return function(x, y) {
            const xi = Math.floor(x), yi = Math.floor(y)
            const xf = x - xi, yf = y - yi
            const u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf)
            const X = xi & 255, Y = yi & 255
            const a = values[perm[perm[X] + Y]], b = values[perm[perm[X + 1] + Y]]
            const c = values[perm[perm[X] + Y + 1]], d = values[perm[perm[X + 1] + Y + 1]]
            return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
        }
    }
    function fbm(noise, x, y, octaves) {
        let sum = 0, amp = 0.5, freq = 1, norm = 0
        for (let o = 0; o < octaves; ++o) {
            sum += noise(x * freq, y * freq) * amp
            norm += amp
            amp *= 0.5
            freq *= 2.03
        }
        return sum / norm
    }
    function smin(a, b, k) {
        const h = Math.max(0, Math.min(1, 0.5 + 0.5 * (b - a) / k))
        return b + (a - b) * h - k * h * (1 - h)
    }

    // The brightness field, cut into levels 0 (blank) to 8.
    function build() {
        const cols = Math.max(1, columns), rowCount = Math.max(1, rows)
        const rand = generator(hashString(seed.length > 0 ? seed : "fireteam"))
        const coast = valueNoise(rand), land = valueNoise(rand), ridges = valueNoise(rand)
        const o1 = rand() * 50, o2 = rand() * 50, o3 = rand() * 50
        // In physical units: the picture is one tall and `aspect` wide.
        const aspect = cols / (rowCount * cellAspect)
        const halfW = aspect / 2
        // A range of masses strung across the width, melted into one
        // silhouette: a ridge of high ground with spurs off it.
        const blobs = []
        const masses = 3 + Math.floor(rand() * 3) + Math.floor(Math.max(0, aspect - 1.5) * 1.5)
        const span = Math.max(0, halfW - 0.36)
        const tilt = (rand() - 0.5) * 0.3
        for (let i = 0; i < masses; ++i) {
            const t = masses === 1 ? 0 : i / (masses - 1) * 2 - 1
            const r = (0.2 + rand() * 0.14) * (1 - 0.35 * Math.abs(t))
            blobs.push({
                x: t * span + (rand() - 0.5) * 0.12,
                y: Math.max(-0.5 + r + 0.06, Math.min(0.5 - r - 0.06, t * tilt + (rand() - 0.5) * 0.22)),
                r: r
            })
        }
        const contourStep = 6 + Math.floor(rand() * 3)
        const lv = new Array(cols * rowCount)
        let peak = -1, peakElev = -1
        for (let r = 0; r < rowCount; ++r) {
            const py = (r + 0.5) / rowCount - 0.5
            for (let c = 0; c < cols; ++c) {
                const px = ((c + 0.5) / cols - 0.5) * aspect
                let sd = 1e9
                for (const b of blobs)
                    sd = smin(sd, Math.hypot(px - b.x, py - b.y) - b.r, 0.18)
                sd += (fbm(coast, px * 3.2 + o1, py * 3.2 + o1, 4) - 0.5) * 0.26
                const index = r * cols + c
                if (sd >= 0) {
                    // Dust off the coast, thinning with distance.
                    const scatter = rand()
                    lv[index] = (sd < 0.07 && scatter < 0.09 * (1 - sd / 0.07)) || scatter < 0.003 ? 1 : 0
                    continue
                }
                const depth = Math.min(1, -sd / 0.26)
                const elev = Math.max(0, Math.min(1, 0.55 * depth + 0.75 * (fbm(land, px * 2.4 + o2, py * 2.4 + o2, 5) - 0.5) + 0.3))
                let bright = 0.08 + 0.42 * elev
                const band = elev * contourStep - Math.floor(elev * contourStep)
                if (band < 0.14) bright = Math.max(bright, 0.6 + 0.4 * elev)
                const ridge = 1 - Math.abs(2 * fbm(ridges, px * 2.8 + o3, py * 2.8 + o3, 3) - 1)
                bright += Math.pow(ridge, 10) * 0.55 * (0.4 + elev)
                if (-sd < 0.016) bright = Math.max(bright, 0.72)
                lv[index] = 1 + Math.floor(Math.max(0, Math.min(0.999, bright)) * 8)
                if (elev > peakElev && -sd > 0.08) { peakElev = elev; peak = index }
            }
        }
        // A survey cross on the summit.
        if (peak >= 0) {
            const pr = Math.floor(peak / cols), pc = peak % cols
            const mark = (r, c) => { if (r >= 0 && r < rowCount && c >= 0 && c < cols) lv[r * cols + c] = 8 }
            for (let k = 2; k <= 4; ++k) { mark(pr, pc - k); mark(pr, pc + k) }
            for (let k = 1; k <= 2; ++k) { mark(pr - k, pc); mark(pr + k, pc) }
        }
        // Each lit cell takes the next character of the source.
        const text = (source.replace(/\s+/g, "·").replace(/^·+|·+$/g, "") || "FIRETEAM")
        const ch = new Array(cols * rowCount), groups = [[], [], [], [], [], [], [], [], []]
        let next = 0
        for (let i = 0; i < lv.length; ++i) {
            if (lv[i] === 0) { ch[i] = ""; continue }
            ch[i] = text.charAt(next % text.length)
            next += 1
            groups[lv[i]].push(i)
        }
        levels = lv
        chars = ch
        byLevel = groups
        flares = ({})
        canvas.requestPaint()
    }

    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
    }
    function css(c) { return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + ",1)" }
    // Eight steps from a dark wash of the accent to the accent, the last paled.
    function colours() {
        const list = [""], tones = [ground]
        for (let level = 1; level <= 8; ++level) {
            const t = (level - 1) / 7
            const c = level < 8 ? mix(ground, accent, 0.2 + 0.8 * Math.pow(t, 0.9))
                                : mix(accent, Qt.rgba(1, 1, 1, 1), 0.35)
            list.push(css(c))
            tones.push(c)
        }
        ramp = list
        rampColours = tones
        flareInk = mix(accent, Qt.rgba(1, 1, 1, 1), 0.2)
        canvas.requestPaint()
    }

    Timer {
        id: resolveClock
        property real started: 0
        interval: 40
        repeat: true
        onTriggered: {
            picture.progress = Math.min(1, (Date.now() - started) / 1200)
            if (picture.progress >= 1) stop()
            canvas.requestPaint()
        }
    }
    Connections {
        target: Prefs
        function onReduceMotionChanged() {
            if (Prefs.reduceMotion && resolveClock.running) {
                resolveClock.stop()
                picture.progress = 1
                canvas.requestPaint()
            }
        }
    }

    // Cells near the cursor flare, then settle.
    Timer {
        id: settle
        interval: 33
        repeat: true
        onTriggered: {
            const list = picture.flares
            if (Object.keys(list).length === 0) { stop(); return }
            // The box before the decay, so cells that drop out get their last paint.
            const box = canvas.flareBox(list, true)
            for (const key in list) {
                list[key] *= 0.84
                if (list[key] < 0.03) delete list[key]
            }
            canvas.markDirty(box)
        }
    }
    HoverHandler {
        id: hover
        enabled: !Prefs.reduceMotion
        onPointChanged: {
            if (!hovered || picture.progress < 1) return
            const g = canvas.grid()
            const pos = point.position
            const reach = 5 * g.cw
            const c0 = Math.max(0, Math.floor((pos.x - g.ox - reach) / g.cw)), c1 = Math.min(picture.columns - 1, Math.floor((pos.x - g.ox + reach) / g.cw))
            const r0 = Math.max(0, Math.floor((pos.y - g.oy - reach) / g.ch)), r1 = Math.min(picture.rows - 1, Math.floor((pos.y - g.oy + reach) / g.ch))
            const list = picture.flares
            let touched = false
            for (let r = r0; r <= r1; ++r)
                for (let c = c0; c <= c1; ++c) {
                    const index = r * picture.columns + c
                    if (!picture.levels[index]) continue
                    const d = Math.hypot(g.ox + (c + 0.5) * g.cw - pos.x, g.oy + (r + 0.5) * g.ch - pos.y) / reach
                    if (d >= 1) continue
                    const v = (1 - d) * (1 - d)
                    if (!(list[index] >= v)) { list[index] = v; touched = true }
                }
            if (touched) {
                canvas.markDirty(canvas.flareBox(list, false))
                settle.start()
            }
        }
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative

        // Where the cells sit: as wide as the item allows, centred.
        function grid() {
            const cols = Math.max(1, picture.columns), rowCount = Math.max(1, picture.rows)
            let cw = width / cols, ch = cw * picture.cellAspect
            if (ch * rowCount > height) { ch = height / rowCount; cw = ch / picture.cellAspect }
            return { cw: cw, ch: ch, ox: (width - cw * cols) / 2, oy: (height - ch * rowCount) / 2 }
        }
        // The box around flaring cells (a cell's margin over, for overhang).
        function flareBox(list, settling) {
            const g = grid()
            let c0 = 1e9, c1 = -1, r0 = 1e9, r1 = -1
            for (const key in list) {
                const r = Math.floor(key / picture.columns), c = key % picture.columns
                c0 = Math.min(c0, c); c1 = Math.max(c1, c); r0 = Math.min(r0, r); r1 = Math.max(r1, r)
            }
            if (c1 < 0) return Qt.rect(0, 0, width, height)
            const pad = settling ? 2 : 1  // a cell's overhang, and one more while settling
            return Qt.rect(g.ox + (c0 - pad) * g.cw, g.oy + (r0 - pad) * g.ch, (c1 - c0 + 1 + 2 * pad) * g.cw, (r1 - r0 + 1 + 2 * pad) * g.ch)
        }

        onPaint: (region) => {
            const ctx = getContext("2d")
            const cols = picture.columns, rowCount = picture.rows
            const levels = picture.levels, chars = picture.chars, ramp = picture.ramp
            if (levels.length !== cols * rowCount || ramp.length < 9) { ctx.reset(); return }
            const g = grid()
            const full = !region || (region.width >= width - 1 && region.height >= height - 1)
            ctx.save()
            if (full) {
                ctx.clearRect(0, 0, width, height)
            } else {
                ctx.beginPath()
                ctx.rect(region.x, region.y, region.width, region.height)
                ctx.clip()
                ctx.clearRect(region.x, region.y, region.width, region.height)
            }
            const c0 = full ? 0 : Math.max(0, Math.floor((region.x - g.ox) / g.cw) - 1)
            const c1 = full ? cols - 1 : Math.min(cols - 1, Math.ceil((region.x + region.width - g.ox) / g.cw) + 1)
            const r0 = full ? 0 : Math.max(0, Math.floor((region.y - g.oy) / g.ch) - 1)
            const r1 = full ? rowCount - 1 : Math.min(rowCount - 1, Math.ceil((region.y + region.height - g.oy) / g.ch) + 1)
            const fullPx = g.cw / metrics.ratio
            const fontFull = Math.max(1, fullPx).toFixed(1) + "px \"" + Style.mono + "\""
            const fontDim = Math.max(1, fullPx * picture.dimScale).toFixed(1) + "px \"" + Style.mono + "\""
            ctx.textAlign = "center"
            ctx.textBaseline = "middle"
            const text = chars

            // Rows the resolve has reached are final; a band of noise runs
            // ahead of it, and sparse static fills the rest.
            const front = picture.progress >= 1 ? rowCount + 4 : picture.progress * (rowCount + 4)
            const settledRow = Math.floor(front) - 3
            const flares = picture.flares
            let font = ""
            for (let level = 1; level <= 8; ++level) {
                const wanted = level <= 3 ? fontDim : fontFull
                if (font !== wanted) { ctx.font = wanted; font = wanted }
                ctx.fillStyle = ramp[level]
                for (const index of picture.byLevel[level]) {
                    const r = Math.floor(index / cols)
                    if (r < r0 || r > r1 || r >= settledRow) continue
                    const c = index - r * cols
                    if (c < c0 || c > c1 || flares[index] !== undefined) continue
                    ctx.fillText(text[index], g.ox + (c + 0.5) * g.cw, g.oy + (r + 0.5) * g.ch)
                }
            }
            if (picture.progress < 1) {
                const source = picture.source.length > 0 ? picture.source : "FIRETEAM"
                for (let r = Math.max(0, settledRow); r < rowCount; ++r) {
                    const inBand = r < front
                    for (let c = 0; c < cols; ++c) {
                        const index = r * cols + c
                        const lit = levels[index] > 0
                        if (inBand ? !(lit || Math.random() < 0.18) : Math.random() > 0.035) continue
                        const level = inBand ? 1 + Math.floor(Math.random() * 8) : 1 + Math.floor(Math.random() * 2)
                        const glyph = source.charAt(Math.floor(Math.random() * source.length))
                        if (glyph.trim().length === 0) continue
                        ctx.font = level <= 3 ? fontDim : fontFull
                        ctx.fillStyle = ramp[level]
                        ctx.fillText(glyph, g.ox + (c + 0.5) * g.cw, g.oy + (r + 0.5) * g.ch)
                    }
                }
            }
            // Flaring cells, full size, washing from their own level to the accent.
            ctx.font = fontFull
            for (const key in flares) {
                const index = Number(key)
                const r = Math.floor(index / cols), c = index - r * cols
                if (r < r0 || r > r1 || c < c0 || c > c1) continue
                const v = flares[key]
                ctx.fillStyle = picture.css(picture.mix(picture.rampColours[levels[index]], picture.flareInk, Math.min(1, v * 1.6)))
                ctx.fillText(text[index], g.ox + (c + 0.5) * g.cw, g.oy + (r + 0.5) * g.ch)
            }
            ctx.restore()
        }
    }
}
