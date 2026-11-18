import SwiftUI

/// What a lesson draws on the board: rings around squares, arrows from one square to another, and squares lit
/// (the ones found on a pick step). Only lessons have marks; a game's or a puzzle's board has none.
struct BoardMarks: Equatable {
    struct Arrow: Hashable { let from: Int; let to: Int }
    var rings: [Int] = []
    var arrows: [Arrow] = []
    var lit: [Int] = []

    init(rings: [Int] = [], arrows: [Arrow] = [], lit: [Int] = []) {
        self.rings = rings
        self.arrows = arrows
        self.lit = lit
    }

    /// From a lesson's marks, by square name; names that are not squares are dropped (the reader already refuses them).
    init(_ m: LessonMarks?, lit: [String] = []) {
        rings = (m?.squares ?? []).compactMap { Square.index($0) }
        arrows = (m?.arrows ?? []).compactMap { a in
            guard a.count == 2, let f = Square.index(a[0]), let t = Square.index(a[1]) else { return nil }
            return Arrow(from: f, to: t)
        }
        self.lit = lit.compactMap { Square.index($0) }
    }

    var isEmpty: Bool { rings.isEmpty && arrows.isEmpty && lit.isEmpty }
}

/// Drawing marks, shared by the lesson's board and the small boards in Learn's lists. Zeist's amber, the mark
/// color its tokens give Puzzles and Classics, so a lesson's marks never read as the last move.
enum MarksArt {
    static func rect(_ i: Int, cell: CGFloat, flipped: Bool) -> CGRect {
        let (c, r) = flipped ? (7 - i % 8, 7 - i / 8) : (i % 8, i / 8)
        return CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: cell, height: cell)
    }

    /// Lit squares: a wash under the pieces.
    static func drawLit(_ ctx: inout GraphicsContext, _ m: BoardMarks, cell: CGFloat, flipped: Bool) {
        for i in m.lit {
            let r = rect(i, cell: cell, flipped: flipped)
            ctx.fill(Path(r), with: .color(Z.lesson.opacity(0.34)))
            ctx.stroke(Path(r.insetBy(dx: 1.25, dy: 1.25)), with: .color(Z.lesson.opacity(0.8)), lineWidth: max(1.5, cell * 0.04))
        }
    }

    /// Rings and arrows: over the pieces, so a ring reads around the piece it names.
    static func drawOver(_ ctx: inout GraphicsContext, _ m: BoardMarks, cell: CGFloat, flipped: Bool) {
        for i in m.rings {
            let r = rect(i, cell: cell, flipped: flipped)
            let w = max(1.5, cell * 0.07)
            ctx.stroke(Path(ellipseIn: r.insetBy(dx: cell * 0.05 + w / 2, dy: cell * 0.05 + w / 2)), with: .color(Z.lesson), lineWidth: w)
        }
        for a in m.arrows {
            let ra = rect(a.from, cell: cell, flipped: flipped), rb = rect(a.to, cell: cell, flipped: flipped)
            let p = CGPoint(x: ra.midX, y: ra.midY), q = CGPoint(x: rb.midX, y: rb.midY)
            let len = hypot(q.x - p.x, q.y - p.y)
            guard len > 0 else { continue }
            let ux = (q.x - p.x) / len, uy = (q.y - p.y) / len
            let head = cell * 0.32, w = max(1.5, cell * 0.11)
            let start = CGPoint(x: p.x + ux * cell * 0.22, y: p.y + uy * cell * 0.22)
            let tip = CGPoint(x: q.x - ux * cell * 0.12, y: q.y - uy * cell * 0.12)
            let neck = CGPoint(x: tip.x - ux * head, y: tip.y - uy * head)
            var shaft = Path(); shaft.move(to: start); shaft.addLine(to: neck)
            var arrow = Path()
            arrow.move(to: tip)
            arrow.addLine(to: CGPoint(x: neck.x - uy * head * 0.6, y: neck.y + ux * head * 0.6))
            arrow.addLine(to: CGPoint(x: neck.x + uy * head * 0.6, y: neck.y - ux * head * 0.6))
            arrow.closeSubpath()
            let ink = Z.lesson.opacity(0.88)
            ctx.stroke(shaft, with: .color(ink), style: StrokeStyle(lineWidth: w, lineCap: .round))
            ctx.fill(arrow, with: .color(ink))
        }
    }
}
