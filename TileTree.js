.pragma library

// The dwindle tree of one workspace, worked out from where its windows are.
//
// Dwindle cuts the workspace in two, then cuts each half again, so every
// split is a straight line from one edge of its box to the other. Finding
// such a line through the gaps, and recursing into both sides, gives the
// tree back. Where two different lines would do (a 2x2 grid), the one
// nearest the middle wins, and on a tie the one dwindle itself would draw:
// side by side when the box is wider than it is tall.
//
// A node is a window { addr, box, rect } or a split
// { axis: "v" | "h", ratio, pos, box, children: [first, second] }, where
// "v" is a vertical line (children side by side) and the ratio is dwindle's,
// 1 for an even split. `box` is the space dwindle gives the node; `rect` is
// the window inside it, short of the gaps.

var EPS = 1

function bounds(wins) {
    var x1 = Infinity, y1 = Infinity, x2 = -Infinity, y2 = -Infinity
    for (var i = 0; i < wins.length; i++) {
        var w = wins[i]
        x1 = Math.min(x1, w.x)
        y1 = Math.min(y1, w.y)
        x2 = Math.max(x2, w.x + w.w)
        y2 = Math.max(y2, w.y + w.h)
    }
    return { x: x1, y: y1, w: x2 - x1, h: y2 - y1 }
}

function cutsAlong(wins, axis) {
    var lo = axis === "v" ? "x" : "y"
    var ext = axis === "v" ? "w" : "h"
    var ends = []
    for (var i = 0; i < wins.length; i++) {
        var e = wins[i][lo] + wins[i][ext]
        if (ends.indexOf(e) < 0)
            ends.push(e)
    }

    var cuts = []
    for (var j = 0; j < ends.length; j++) {
        var end = ends[j]
        var first = [], second = [], start = Infinity, clean = true
        for (var k = 0; k < wins.length; k++) {
            var w = wins[k]
            if (w[lo] + w[ext] <= end + EPS) {
                first.push(w)
            } else if (w[lo] > end) {
                second.push(w)
                start = Math.min(start, w[lo])
            } else {
                clean = false
                break
            }
        }
        if (clean && first.length && second.length)
            cuts.push({ axis: axis, pos: (end + start) / 2, first: first, second: second })
    }
    return cuts
}

function addrSet(wins) {
    return wins.map(function (w) { return w.addr }).sort().join(",")
}

function bestCut(wins, box, hint) {
    var cuts = cutsAlong(wins, "v").concat(cutsAlong(wins, "h"))

    // The tree this shell last built here, when the windows still allow its
    // split, beats any guess.
    if (hint && hint.children) {
        var a = leafAddrs(hint.children[0]), b = leafAddrs(hint.children[1])
        for (var h = 0; h < cuts.length; h++) {
            if (cuts[h].axis === hint.axis && addrSet(cuts[h].first) === a && addrSet(cuts[h].second) === b)
                return cuts[h]
        }
    }

    var wide = box.w > box.h
    var best = null, bestScore = Infinity
    for (var i = 0; i < cuts.length; i++) {
        var c = cuts[i]
        var mid = c.axis === "v" ? box.x + box.w / 2 : box.y + box.h / 2
        var span = c.axis === "v" ? box.w : box.h
        var score = Math.abs(c.pos - mid) / span
        // Prefer dwindle's own direction on a tie.
        if ((c.axis === "v") !== wide)
            score += 0.001
        if (score < bestScore) {
            best = c
            bestScore = score
        }
    }
    return best
}

function leafAddrs(n) {
    var out = []
    ;(function walk(m) {
        if (m.children) {
            walk(m.children[0])
            walk(m.children[1])
        } else {
            out.push(m.addr)
        }
    })(n)
    return out.sort().join(",")
}

function grow(wins, box, parent, hint) {
    if (wins.length === 1) {
        var w = wins[0]
        return { addr: w.addr, box: box, rect: { x: w.x, y: w.y, w: w.w, h: w.h }, parent: parent }
    }

    var cut = bestCut(wins, box, hint)
    if (!cut)
        return null
    var followed = hint && hint.children && cut.axis === hint.axis
        && addrSet(cut.first) === leafAddrs(hint.children[0])

    var node = { axis: cut.axis, pos: cut.pos, box: box, parent: parent, children: [] }
    var a, b
    if (cut.axis === "v") {
        a = { x: box.x, y: box.y, w: cut.pos - box.x, h: box.h }
        b = { x: cut.pos, y: box.y, w: box.x + box.w - cut.pos, h: box.h }
        node.ratio = 2 * (cut.pos - box.x) / box.w
    } else {
        a = { x: box.x, y: box.y, w: box.w, h: cut.pos - box.y }
        b = { x: box.x, y: cut.pos, w: box.w, h: box.y + box.h - cut.pos }
        node.ratio = 2 * (cut.pos - box.y) / box.h
    }
    node.ratio = Math.min(1.9, Math.max(0.1, node.ratio))

    var first = grow(cut.first, a, node, followed ? hint.children[0] : null)
    var second = grow(cut.second, b, node, followed ? hint.children[1] : null)
    if (!first || !second)
        return null
    node.children = [first, second]
    return node
}

// wins: [{ addr, x, y, w, h }]. Returns the root, or null when the windows
// do not tile the space the way dwindle would (pseudotiled, overlapping).
// `hint` is a tree from swapped(), the shape last built here.
function build(wins, hint) {
    if (!wins || !wins.length)
        return null
    return grow(wins, bounds(wins), null, hint || null)
}

function isLeaf(n) {
    return !n.children
}

function leaves(n, out) {
    out = out || []
    if (isLeaf(n)) {
        out.push(n)
    } else {
        leaves(n.children[0], out)
        leaves(n.children[1], out)
    }
    return out
}

// The same windows make the same group, wherever it sits, so a group stays
// picked across the rebuild that moves it.
function keyOf(n) {
    return leaves(n).map(function (l) { return l.addr }).sort().join(",")
}

function find(n, key) {
    if (!n)
        return null
    if (keyOf(n) === key)
        return n
    if (isLeaf(n))
        return null
    return find(n.children[0], key) || find(n.children[1], key)
}

function within(n, ancestor) {
    for (var p = n; p; p = p.parent) {
        if (p === ancestor)
            return true
    }
    return false
}

function splits(n, out) {
    out = out || []
    if (!isLeaf(n)) {
        out.push(n)
        splits(n.children[0], out)
        splits(n.children[1], out)
    }
    return out
}

// Where a group's dot goes: the middle of its own split line, between the
// two sides it joins. Two lines never share a middle in a dwindle tree, but
// a dot is stepped along its line if another sits within `gap` of it. The
// whole workspace is not a group.
function handles(root, gap) {
    var out = []
    if (!root || isLeaf(root))
        return out

    var all = splits(root)
    for (var i = 0; i < all.length; i++) {
        var n = all[i]
        if (n === root)
            continue

        var vertical = n.axis === "v"
        var start = vertical ? n.box.y : n.box.x
        var length = vertical ? n.box.h : n.box.w
        var spot = null
        for (var k = 0; k <= 8 && spot === null; k++) {
            for (var sign = 1; sign >= -1 && spot === null; sign -= 2) {
                var along = start + length / 2 + sign * k * gap
                var px = vertical ? n.pos : along
                var py = vertical ? along : n.pos
                var free = true
                for (var o = 0; o < out.length; o++) {
                    if (Math.abs(out[o].x - px) < gap && Math.abs(out[o].y - py) < gap)
                        free = false
                }
                if (free)
                    spot = { x: px, y: py }
                if (k === 0)
                    break
            }
        }
        if (!spot)
            spot = vertical ? { x: n.pos, y: start + length / 2 } : { x: start + length / 2, y: n.pos }
        out.push({ node: n, key: keyOf(n), x: spot.x, y: spot.y })
    }
    return out
}

// The neighbour a group trades places with when moved one step: the branch
// across the nearest split line in that direction, narrowed down to the part
// that lines up with the group, so a step moves it next door rather than
// swapping it with half the screen.
function neighbour(node, dir) {
    var axis = (dir === "l" || dir === "r") ? "v" : "h"
    var forward = (dir === "r" || dir === "d")

    var child = node, parent = node.parent
    while (parent) {
        var side = parent.children[0] === child ? 0 : 1
        if (parent.axis === axis && side === (forward ? 0 : 1))
            break
        child = parent
        parent = parent.parent
    }
    if (!parent)
        return null

    var lo = axis === "v" ? "y" : "x"
    var ext = axis === "v" ? "h" : "w"
    var other = parent.children[forward ? 1 : 0]
    while (!isLeaf(other)) {
        if (other.axis === axis) {
            other = other.children[forward ? 0 : 1]
            continue
        }
        // A line across the direction of travel: go into the side the
        // group fits in, if it fits in one.
        var a = other.children[0], b = other.children[1]
        var start = node.box[lo], end = node.box[lo] + node.box[ext]
        if (end <= a.box[lo] + a.box[ext] + EPS)
            other = a
        else if (start >= b.box[lo] - EPS)
            other = b
        else
            break
    }
    return other
}

function addressOk(addr) {
    return /^0x[0-9a-fA-F]+$/.test(addr)
}

// The tree with branches a and b traded, as a bare { axis, ratio,
// children } / { addr } structure, or null when the trade would mean
// nothing (the same branch, or one inside the other).
function swapped(root, a, b) {
    if (!root || !a || !b || a === b || within(a, b) || within(b, a))
        return null
    return copy(root, a, b)
}

function copy(n, a, b) {
    if (n === a)
        return plain(b)
    if (n === b)
        return plain(a)
    if (isLeaf(n))
        return { addr: n.addr }
    return { axis: n.axis, ratio: n.ratio, children: [copy(n.children[0], a, b), copy(n.children[1], a, b)] }
}

function plain(n) {
    if (isLeaf(n))
        return { addr: n.addr }
    return { axis: n.axis, ratio: n.ratio, children: [plain(n.children[0]), plain(n.children[1])] }
}

// A tree from swapped() as a Lua table for QsTiles.apply.
function lua(n) {
    if (!n.children) {
        if (!addressOk(n.addr))
            throw new Error("bad window address " + n.addr)
        return "{a='" + n.addr + "'}"
    }
    return "{s='" + n.axis + "',r=" + n.ratio.toFixed(4)
        + ",c={" + lua(n.children[0]) + "," + lua(n.children[1]) + "}}"
}

// The windows of a branch as drawn: the box around their rects.
function rectOf(n) {
    var ls = leaves(n)
    var x1 = Infinity, y1 = Infinity, x2 = -Infinity, y2 = -Infinity
    for (var i = 0; i < ls.length; i++) {
        var r = ls[i].rect
        x1 = Math.min(x1, r.x)
        y1 = Math.min(y1, r.y)
        x2 = Math.max(x2, r.x + r.w)
        y2 = Math.max(y2, r.y + r.h)
    }
    return { x: x1, y: y1, w: x2 - x1, h: y2 - y1 }
}

// What makes a group look like one piece: the gaps between its windows
// filled in (strips), and the round window corners that face into the group
// filled out (corners), so only the group's own outline stays round. Where
// an inner gap reaches the group's edge, the two corners there stay round:
// a small notch that still shows the seam. The fill ends there in a bowl as
// wide as the gap, so the notch dips into the group in a round point. `radius` is the window rounding.
//
// A corner { x, y, turn, r } is the r-sized square at the point (x, y) short
// of the quarter circle facing away from it: turn 0 has the point at its top
// left, 90 top right, 180 bottom right, 270 bottom left.
// Nothing reaches under a window: the windows are see-through, and a fill
// behind one darkens it.
function fusion(node, radius) {
    var out = { strips: [], corners: [] }
    if (!node || isLeaf(node))
        return out

    var g = rectOf(node)
    var all = splits(node)
    for (var i = 0; i < all.length; i++) {
        var s = all[i]
        var a = rectOf(s.children[0]), b = rectOf(s.children[1]), r = rectOf(s)
        if (s.axis === "v") {
            var gx = b.x - (a.x + a.w)
            var x1 = a.x + a.w, half = gx / 2
            var top = r.y + radius, bottom = r.y + r.h - radius
            if (r.y <= g.y + EPS) {
                top += half
                out.corners.push({ x: x1, y: top, turn: 270, r: half })
                out.corners.push({ x: x1 + gx, y: top, turn: 180, r: half })
            } else {
                top = r.y - gx
            }
            if (r.y + r.h >= g.y + g.h - EPS) {
                bottom -= half
                out.corners.push({ x: x1, y: bottom, turn: 0, r: half })
                out.corners.push({ x: x1 + gx, y: bottom, turn: 90, r: half })
            } else {
                bottom = r.y + r.h + gx
            }
            out.strips.push({ x: x1, y: top, w: gx, h: bottom - top })
        } else {
            var gy = b.y - (a.y + a.h)
            var y1 = a.y + a.h, halfY = gy / 2
            var left = r.x + radius, right = r.x + r.w - radius
            if (r.x <= g.x + EPS) {
                left += halfY
                out.corners.push({ x: left, y: y1, turn: 90, r: halfY })
                out.corners.push({ x: left, y: y1 + gy, turn: 180, r: halfY })
            } else {
                left = r.x - gy
            }
            if (r.x + r.w >= g.x + g.w - EPS) {
                right -= halfY
                out.corners.push({ x: right, y: y1, turn: 0, r: halfY })
                out.corners.push({ x: right, y: y1 + gy, turn: 270, r: halfY })
            } else {
                right = r.x + r.w + gy
            }
            out.strips.push({ x: left, y: y1, w: right - left, h: gy })
        }
    }

    var ls = leaves(node)
    for (var j = 0; j < ls.length; j++) {
        var lr = ls[j].rect
        var pts = [
            { x: lr.x, y: lr.y, turn: 0, r: radius },
            { x: lr.x + lr.w, y: lr.y, turn: 90, r: radius },
            { x: lr.x + lr.w, y: lr.y + lr.h, turn: 180, r: radius },
            { x: lr.x, y: lr.y + lr.h, turn: 270, r: radius }
        ]
        for (var k = 0; k < pts.length; k++) {
            var p = pts[k]
            var edgeX = Math.abs(p.x - g.x) <= EPS || Math.abs(p.x - (g.x + g.w)) <= EPS
            var edgeY = Math.abs(p.y - g.y) <= EPS || Math.abs(p.y - (g.y + g.h)) <= EPS
            if (!edgeX && !edgeY)
                out.corners.push(p)
        }
    }
    return out
}

// The window under a point, for dropping a dragged group onto it.
function leafAt(root, x, y) {
    if (!root)
        return null
    var all = leaves(root)
    for (var i = 0; i < all.length; i++) {
        var b = all[i].box
        if (x >= b.x && x < b.x + b.w && y >= b.y && y < b.y + b.h)
            return all[i]
    }
    return null
}
