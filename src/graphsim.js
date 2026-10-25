.pragma library

// A small force simulation for the knowledge graph, in two dimensions or
// three: nodes push each other apart, links pull like springs, a little
// gravity keeps the whole near the middle, and it cools until it's still.
// Dragging a node pins it and warms the rest so they follow. Positions are in
// a space about -1..1; project() turns them into the panel's 0..1 field.

function hash(i) {
    // A fixed scatter for the third dimension, the same every time.
    const s = Math.sin(i * 12.9898 + 78.233) * 43758.5453
    return s - Math.floor(s)
}

// nodes: [{x, y}] in 0..1 (the laid-out map), links: [{a, b, weight?}].
function create(nodes, links, threeD) {
    const state = {
        nodes: nodes.map((n, i) => ({
            x: (n.x - 0.5) * 2, y: (n.y - 0.5) * 2,
            z: threeD ? (hash(i) - 0.5) * 1.4 : 0,
            vx: 0, vy: 0, vz: 0, pinned: false
        })),
        links: links.map(l => ({ a: l.a, b: l.b, w: Math.min(3, 0.6 + Math.log(1 + (l.weight || 1)) * 0.5) })),
        threeD: threeD,
        // The map arrives laid out, so a 2D start only settles; 3D has to
        // find its depth, so it starts warmer.
        alpha: threeD ? 0.9 : 0.25,
        degree: [],
        // The camera's framing: field = 0.5 + (point - centre) * scale, eased
        // toward fitting everything, and held still while a node is dragged.
        view: { cx: 0, cy: 0, sx: 0.5, sy: 0.5 },
        held: false
    }
    state.degree = state.nodes.map(() => 0)
    for (const l of state.links) {
        state.degree[l.a] += 1
        state.degree[l.b] += 1
    }
    // Lone files have no springs; they rest on a ring further out.
    state.length = 1.6 / Math.sqrt(Math.max(4, nodes.length))
    return state
}

function warm(state, alpha) { state.alpha = Math.max(state.alpha, alpha) }
function settled(state) { return state.alpha < 0.004 }

function step(state) {
    const nodes = state.nodes, n = nodes.length, alpha = state.alpha, three = state.threeD
    if (n === 0 || settled(state)) return
    const length = state.length, charge = length * length * 0.08
    // Repulsion, every pair (the graphs here are files or one file's symbols:
    // hundreds at most).
    for (let i = 0; i < n; ++i) {
        const p = nodes[i]
        for (let j = i + 1; j < n; ++j) {
            const q = nodes[j]
            let dx = p.x - q.x, dy = p.y - q.y, dz = three ? p.z - q.z : 0
            let d2 = dx * dx + dy * dy + dz * dz
            if (d2 < 1e-6) { dx = (hash(i + j) - 0.5) * 1e-3; dy = (hash(i * j + 1) - 0.5) * 1e-3; d2 = 1e-6 }
            if (d2 > 2) continue
            const f = charge / d2 * alpha
            p.vx += dx * f; p.vy += dy * f; q.vx -= dx * f; q.vy -= dy * f
            if (three) { p.vz += dz * f; q.vz -= dz * f }
        }
    }
    // Springs.
    for (const l of state.links) {
        const p = nodes[l.a], q = nodes[l.b]
        if (!p || !q) continue
        const dx = q.x - p.x, dy = q.y - p.y, dz = three ? q.z - p.z : 0
        const d = Math.sqrt(dx * dx + dy * dy + dz * dz) || 1e-4
        const f = (d - length) / d * 0.1 * l.w * alpha
        p.vx += dx * f; p.vy += dy * f; q.vx -= dx * f; q.vy -= dy * f
        if (three) { p.vz += dz * f; q.vz -= dz * f }
    }
    // Gravity to the middle (stronger for lone files, which have no springs),
    // then move with friction.
    for (let i = 0; i < n; ++i) {
        const p = nodes[i]
        const g = (state.degree[i] === 0 ? (three ? 0.08 : 0.02) : 0.012) * alpha
        p.vx -= p.x * g; p.vy -= p.y * g
        if (three) p.vz -= p.z * g
        if (p.pinned) { p.vx = p.vy = p.vz = 0; continue }
        p.vx *= 0.62; p.vy *= 0.62; p.vz *= 0.62
        p.x += p.vx; p.y += p.vy
        if (three) p.z += p.vz
    }
    state.alpha *= 0.982
}

// Where each node lands in the 0..1 field, with depth and a size factor:
// [{x, y, depth, scale}]. In 3D the camera turns by yaw (around the vertical)
// and pitch, and nearer nodes come out bigger.
function camera(state, p, yaw, pitch) {
    if (!state.threeD)
        return { x: p.x, y: p.y, depth: 0, scale: 1 }
    const cy = Math.cos(yaw), sy = Math.sin(yaw), cp = Math.cos(pitch), sp = Math.sin(pitch)
    const x1 = p.x * cy + p.z * sy, z1 = -p.x * sy + p.z * cy
    const y2 = p.y * cp - z1 * sp, z2 = p.y * sp + z1 * cp
    const f = 3 / (3 - Math.max(-2, Math.min(2, z2)))
    return { x: x1 * f, y: y2 * f, depth: z2, scale: f }
}

function project(state, yaw, pitch) {
    const seen = state.nodes.map(p => camera(state, p, yaw, pitch))
    // Ease the framing toward everything in view, unless a node is held.
    if (seen.length > 0 && !state.held) {
        let minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9
        for (const c of seen) {
            minX = Math.min(minX, c.x); maxX = Math.max(maxX, c.x)
            minY = Math.min(minY, c.y); maxY = Math.max(maxY, c.y)
        }
        let sx = 0.88 / Math.max(0.05, maxX - minX), sy = 0.88 / Math.max(0.05, maxY - minY)
        // A wide field may stretch the map, but not past twice either way.
        sx = Math.min(sx, sy * 2.2); sy = Math.min(sy, sx * 2.2)
        const v = state.view, k = 0.12
        v.cx += ((minX + maxX) / 2 - v.cx) * k
        v.cy += ((minY + maxY) / 2 - v.cy) * k
        v.sx += (sx - v.sx) * k
        v.sy += (sy - v.sy) * k
    }
    const v = state.view
    return seen.map(c => ({ x: 0.5 + (c.x - v.cx) * v.sx, y: 0.5 + (c.y - v.cy) * v.sy, depth: c.depth, scale: c.scale }))
}

// Moves a held node so it sits under the pointer at (fx, fy) in the 0..1
// field, keeping its depth in 3D.
function dragTo(state, index, fx, fy, yaw, pitch) {
    const p = state.nodes[index]
    if (!p) return
    const v = state.view
    const px = (fx - 0.5) / v.sx + v.cx, py = (fy - 0.5) / v.sy + v.cy
    if (!state.threeD) {
        p.x = px
        p.y = py
        return
    }
    const cy = Math.cos(yaw), sy = Math.sin(yaw), cp = Math.cos(pitch), sp = Math.sin(pitch)
    // The node's depth from the camera stays; x and y follow the pointer.
    const z1 = -p.x * sy + p.z * cy
    const z2 = p.y * sp + z1 * cp
    const f = 3 / (3 - Math.max(-2, Math.min(2, z2)))
    const x1 = px / f, y2 = py / f
    // Back through the pitch, then the yaw.
    const z1b = -y2 * sp + z2 * cp
    p.y = y2 * cp + z2 * sp
    p.x = x1 * cy - z1b * sy
    p.z = x1 * sy + z1b * cy
}
