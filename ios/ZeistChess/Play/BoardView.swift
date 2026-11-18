import SwiftUI

/// What the board needs from what drives it: a game against an engine (GameModel) or a puzzle (PuzzleModel).
@MainActor
protocol BoardModel: AnyObject {
    var snap: Snapshot { get }
    /// Each square's piece identity, so a piece glides when it moves instead of jumping.
    var ids: [Int?] { get }
    var selected: Int? { get set }
    var promoting: (from: Int, to: Int)? { get set }
    var whiteAtBottom: Bool { get }
    /// The move being looked at while stepping back; nil for the live position.
    var viewPly: Int? { get }
    var shownBoard: [String] { get }
    var shownLast: String? { get }
    /// The side whose pieces are picked up, "w" or "b".
    var player: String { get }
    var premove: (from: Int, to: Int)? { get }
    var hint: (from: Int, to: Int)? { get }
    var canPremove: Bool { get }
    func hints(from i: Int) -> [(to: Int, capture: Bool)]
    func canLift(_ i: Int) -> Bool
    func tap(_ i: Int)
    func drop(from: Int, to: Int)
    func promote(_ piece: String)
    /// Rings, arrows and lit squares: only a lesson has them.
    var marks: BoardMarks? { get }
}

extension BoardModel {
    var marks: BoardMarks? { nil }
}

extension GameModel: BoardModel {}

/// The board: slate squares, ivory and ebony pieces, the last move in a quiet warm tint.
/// Tap a piece then a square, or drag it. Pieces carry identities, so they glide when they move.
struct BoardView<Model: BoardModel>: View {
    let model: Model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: (from: Int, at: CGPoint)?
    @State private var pressStart: Int?
    @AppStorage(Look.key) private var themeID = Themes.file.default
    @AppStorage(Look.coordinatesKey) private var coordinates = true
    /// Square corners, for the edge-to-edge board.
    var square = false

    private var flipped: Bool { !model.whiteAtBottom }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cell = side / 8
            // Edge to edge only when the board really reaches both edges; on a short screen it keeps its corners.
            let flush = square && side >= geo.size.width - 1
            ZStack(alignment: .topLeading) {
                squares(side: side, cell: cell)
                targets(cell: cell)
                pieces(cell: cell)
                if let m = model.marks { over(m, cell: cell) }
                if let p = model.promoting { promotion(p, cell: cell) }
                cells(cell: cell)
            }
            .frame(width: side, height: side, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: flush ? 0 : 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Z.ink.opacity(flush ? 0 : 0.22), lineWidth: 1))
            .contentShape(Rectangle())
            .gesture(model.promoting == nil ? touches(cell: cell) : nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: Geometry

    /// Where board square i sits on screen (column, row), turned for Black.
    private func spot(_ i: Int) -> (Int, Int) { flipped ? (7 - i % 8, 7 - i / 8) : (i % 8, i / 8) }
    private func rect(_ i: Int, _ cell: CGFloat) -> CGRect {
        let (c, r) = spot(i)
        return CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: cell, height: cell)
    }
    private func square(at p: CGPoint, _ cell: CGFloat) -> Int? {
        let c = Int(floor(p.x / cell)), r = Int(floor(p.y / cell))
        guard (0..<8).contains(c), (0..<8).contains(r) else { return nil }
        return flipped ? (7 - r) * 8 + (7 - c) : r * 8 + c
    }

    // MARK: Drawing

    private var theme: BoardTheme { Themes.named(themeID) }

    private func squares(side: CGFloat, cell: CGFloat) -> some View {
        let last = model.shownLast.map { ($0.prefix(2), $0.dropFirst(2).prefix(2)) }
        let from = last.flatMap { Square.index($0.0) }, to = last.flatMap { Square.index($0.1) }
        let check = model.viewPly == nil ? model.snap.check.flatMap { Square.index($0) } : nil
        let pre = model.premove
        let sel = model.selected ?? drag?.from
        let t = theme, m = t.marks
        return ZStack {
            BoardGround(theme: t, flipped: flipped).equatable()
            Canvas { ctx, _ in
                let mark = Color(hex: m.last)
                if let from { ctx.fill(Path(rect(from, cell)), with: .color(mark.opacity(m.last_from))) }
                if let to {
                    ctx.fill(Path(rect(to, cell)), with: .color(mark.opacity(m.last_to)))
                    ctx.stroke(Path(rect(to, cell).insetBy(dx: 1.25, dy: 1.25)), with: .color(mark.opacity(m.last_outline)), lineWidth: 2.5)
                }
                if let sel {
                    let sc = Color(hex: m.selected)
                    ctx.fill(Path(rect(sel, cell)), with: .color(sc.opacity(m.selected_opacity)))
                    ctx.stroke(Path(rect(sel, cell).insetBy(dx: 1.25, dy: 1.25)), with: .color(sc.opacity(0.75)), lineWidth: 2.5)
                }
                if let pre {
                    // A premove: both squares in a cool, quiet wash, the destination outlined in dashes.
                    let pc = Color(hex: m.selected)
                    ctx.fill(Path(rect(pre.from, cell)), with: .color(pc.opacity(m.selected_opacity * 0.8)))
                    ctx.fill(Path(rect(pre.to, cell)), with: .color(pc.opacity(m.selected_opacity)))
                    ctx.stroke(Path(rect(pre.to, cell).insetBy(dx: 1.5, dy: 1.5)), with: .color(pc.opacity(0.7)),
                               style: StrokeStyle(lineWidth: 2, dash: [cell * 0.12, cell * 0.08]))
                }
                if let check {
                    let r = rect(check, cell), c = Color(hex: m.check)
                    ctx.fill(Path(ellipseIn: r.insetBy(dx: -cell * 0.1, dy: -cell * 0.1)),
                             with: .radialGradient(Gradient(colors: [c.opacity(0.95), c.opacity(0.35), c.opacity(0)]),
                                                   center: CGPoint(x: r.midX, y: r.midY), startRadius: 0, endRadius: cell * 0.62))
                }
                if let m = model.marks { MarksArt.drawLit(&ctx, m, cell: cell, flipped: flipped) }
                if coordinates { Coordinates.draw(&ctx, theme: t, flipped: flipped, side: side) }
                if let h = model.hint, model.viewPly == nil {
                    // A hint: a soft arrow from the piece to its square.
                    let a = CGPoint(x: rect(h.from, cell).midX, y: rect(h.from, cell).midY)
                    let b = CGPoint(x: rect(h.to, cell).midX, y: rect(h.to, cell).midY)
                    let len = hypot(b.x - a.x, b.y - a.y), ux = (b.x - a.x) / len, uy = (b.y - a.y) / len
                    let head = cell * 0.34, w = cell * 0.15
                    let start = CGPoint(x: a.x + ux * cell * 0.28, y: a.y + uy * cell * 0.28)
                    let neck = CGPoint(x: b.x - ux * head, y: b.y - uy * head)
                    var shaft = Path(); shaft.move(to: start); shaft.addLine(to: neck)
                    var tip = Path()
                    tip.move(to: b)
                    tip.addLine(to: CGPoint(x: neck.x - uy * head * 0.62, y: neck.y + ux * head * 0.62))
                    tip.addLine(to: CGPoint(x: neck.x + uy * head * 0.62, y: neck.y - ux * head * 0.62))
                    tip.closeSubpath()
                    let ink = Color(hex: m.selected).opacity(0.62)
                    ctx.stroke(shaft, with: .color(ink), style: StrokeStyle(lineWidth: w, lineCap: .round))
                    ctx.fill(tip, with: .color(ink))
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// A lesson's rings and arrows, over the pieces. Never drawn for a game or a puzzle (their marks are nil).
    private func over(_ m: BoardMarks, cell: CGFloat) -> some View {
        Canvas { ctx, _ in MarksArt.drawOver(&ctx, m, cell: cell, flipped: flipped) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.opacity)
    }

    private func targets(cell: CGFloat) -> some View {
        let from = model.selected ?? drag?.from
        let list = from.map { model.hints(from: $0) } ?? []
        let ahead = model.canPremove
        return ForEach(list, id: \.to) { hint in
            let i = hint.to
            Group {
                if ahead {
                    Circle().fill(Color(hex: theme.marks.hint).opacity(theme.marks.hint_opacity * 0.7)).padding(cell * 0.4)
                } else if hint.capture {
                    Circle().strokeBorder(Color(hex: theme.marks.hint).opacity(theme.marks.hint_opacity * 1.3), lineWidth: max(2.5, cell * 0.075)).padding(cell * 0.04)
                } else {
                    Circle().fill(Color(hex: theme.marks.hint).opacity(theme.marks.hint_opacity)).padding(cell * 0.355)
                }
            }
            .frame(width: cell, height: cell)
            .offset(x: rect(i, cell).minX, y: rect(i, cell).minY)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
        .animation(.easeOut(duration: 0.12), value: from)
        .accessibilityHidden(true)
    }

    private struct Placed: Identifiable { let id: Int; let square: Int; let piece: String }

    private func pieces(cell: CGFloat) -> some View {
        let placed: [Placed]
        if model.viewPly != nil {
            // Looking back: pieces keyed by square and kind, so unchanged pieces stay put between steps.
            let board = model.shownBoard
            placed = (0..<64).compactMap { i in board[i].isEmpty ? nil : Placed(id: -(i * 16 + (board[i].hashValue & 15)) - 1, square: i, piece: board[i]) }
        } else {
            placed = (0..<64).compactMap { i -> Placed? in
                let p = model.snap.board[i]
                guard !p.isEmpty, let id = model.ids[i] else { return nil }
                return Placed(id: id, square: i, piece: p)
            }
        }
        return ForEach(placed) { p in
            let lifted = drag?.from == p.square
            let r = rect(p.square, cell)
            PieceImage(piece: p.piece)
                .frame(width: cell * 0.9, height: cell * 0.9)
                .shadow(color: .black.opacity(lifted ? 0.5 : 0.32), radius: lifted ? cell * 0.12 : cell * 0.035, y: lifted ? cell * 0.1 : cell * 0.03)
                .scaleEffect(lifted ? 1.18 : 1)
                .frame(width: cell, height: cell)
                .offset(x: lifted ? drag!.at.x - cell / 2 : r.minX, y: lifted ? drag!.at.y - cell * 0.75 : r.minY)
                .zIndex(lifted ? 10 : 0)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .allowsHitTesting(false)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.26), value: model.snap.last)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: model.viewPly)
        .accessibilityHidden(true)
    }

    private func promotion(_ p: (from: Int, to: Int), cell: CGFloat) -> some View {
        let color = model.player
        let r = rect(p.to, cell)
        let down = r.minY < cell * 4
        return ZStack(alignment: .topLeading) {
            Color.black.opacity(0.35).contentShape(Rectangle()).onTapGesture { model.promoting = nil }
            VStack(spacing: 0) {
                ForEach(down ? ["q", "r", "b", "n"] : ["n", "b", "r", "q"], id: \.self) { k in
                    Button { model.promote(k) } label: {
                        PieceImage(piece: color + k.uppercased()).padding(cell * 0.06).frame(width: cell, height: cell).contentShape(Rectangle())
                    }
                    .buttonStyle(Press())
                    .accessibilityLabel(["q": "Queen", "r": "Rook", "b": "Bishop", "n": "Knight"][k]!)
                    .accessibilityIdentifier("promote-\(k)")
                }
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Z.raised))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Z.hair, lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
            .offset(x: r.minX, y: down ? r.minY : r.maxY - cell * 4)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    /// One element per square for VoiceOver and UI tests. Touches pass through to the board's gesture.
    private func cells(cell: CGFloat) -> some View {
        ForEach(0..<64, id: \.self) { i in
            let r = rect(i, cell)
            Color.clear
                .frame(width: cell, height: cell)
                .offset(x: r.minX, y: r.minY)
                .accessibilityElement()
                .accessibilityLabel(label(i))
                .accessibilityIdentifier("sq-\(Square.name(i))")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { model.tap(i) }
                .allowsHitTesting(false)
        }
    }

    private func label(_ i: Int) -> String {
        let p = model.shownBoard[i]
        let names = ["K": "king", "Q": "queen", "R": "rook", "B": "bishop", "N": "knight", "P": "pawn"]
        var s = Square.name(i)
        if !p.isEmpty { s += ", \(p.hasPrefix("w") ? "white" : "black") \(names[String(p.suffix(1))] ?? "")" }
        if model.selected == i { s += ", selected" }
        if let sel = model.selected, model.hints(from: sel).contains(where: { $0.to == i }) { s += model.canPremove ? ", premove" : ", legal move" }
        if let pre = model.premove, pre.from == i || pre.to == i { s += ", premove set" }
        if let h = model.hint { if h.from == i { s += ", hint: move this piece" } else if h.to == i { s += ", hint: to here" } }
        if let m = model.marks {
            if m.lit.contains(i) { s += ", highlighted" }
            if m.rings.contains(i) { s += ", marked" }
        }
        return s
    }

    // MARK: Touch

    private func touches(cell: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                if pressStart == nil { pressStart = square(at: v.startLocation, cell) ?? -1 }
                guard let s = pressStart, s >= 0 else { return }
                let moved = hypot(v.translation.width, v.translation.height) > max(6, cell * 0.12)
                if drag == nil, moved, model.canLift(s) {
                    drag = (s, v.location)
                    if model.selected != s { Feel.shared.select() }
                    model.selected = nil
                } else if drag != nil {
                    drag = (drag!.from, v.location)
                }
            }
            .onEnded { v in
                defer { pressStart = nil }
                if let d = drag {
                    drag = nil
                    if let to = square(at: v.location, cell), to != d.from { model.drop(from: d.from, to: to) }
                    else { model.selected = d.from }
                } else if let s = pressStart, s >= 0 {
                    model.tap(s)
                }
            }
    }
}

/// A piece, lit: ivory or ebony (ios/scripts/pieces.py), in the set chosen in Settings, or in the set given.
struct PieceImage: View {
    let piece: String
    var set: String? = nil
    @AppStorage(Look.piecesKey) private var chosen = PieceSets.file.default

    var body: some View {
        Image(PieceSets.image(piece, set: set ?? chosen)).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
    }
}

/// A still board from a FEN, for Home, Recent and the game log. With setUp, the pieces arrive once, rank by rank.
struct BoardStill: View {
    let fen: String
    var flipped = false
    var last: String? = nil
    var setUp = false
    /// Files and ranks, when the setting has them on (the game's board and going through a game).
    var coordinates = false
    /// A lesson's rings and arrows, on the small boards in Learn. Nil everywhere else.
    var marks: BoardMarks? = nil
    @AppStorage(Look.coordinatesKey) private var coordinatesOn = true
    @AppStorage(Look.key) private var themeID = Themes.file.default
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        let board = Square.board(fromFEN: fen)
        let theme = Themes.named(themeID)
        let from = last.flatMap { Square.index($0.prefix(2)) }, to = last.flatMap { Square.index($0.dropFirst(2).prefix(2)) }
        GeometryReader { geo in
            let cell = min(geo.size.width, geo.size.height) / 8
            ZStack(alignment: .topLeading) {
                BoardGround(theme: theme, flipped: flipped).equatable()
                Canvas { ctx, _ in
                    let mark = Color(hex: theme.marks.last)
                    for i in [from, to].compactMap({ $0 }) {
                        let (c, r) = flipped ? (7 - i % 8, 7 - i / 8) : (i % 8, i / 8)
                        let rr = CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: cell, height: cell)
                        ctx.fill(Path(rr), with: .color(mark.opacity(i == to ? theme.marks.last_to : theme.marks.last_from)))
                        if i == to { ctx.stroke(Path(rr.insetBy(dx: 1, dy: 1)), with: .color(mark.opacity(theme.marks.last_outline)), lineWidth: max(1, cell * 0.04)) }
                    }
                    if coordinates && coordinatesOn { Coordinates.draw(&ctx, theme: theme, flipped: flipped, side: cell * 8) }
                }
                ForEach(0..<64, id: \.self) { i in
                    if !board[i].isEmpty {
                        let (c, r) = flipped ? (7 - i % 8, 7 - i / 8) : (i % 8, i / 8)
                        // Setting up: the back ranks first, then the pawns, each a beat after the last.
                        let row = flipped ? 7 - r : r
                        let order = Double([0, 2, 0, 0, 0, 0, 3, 1][row]) + Double(c) * 0.08
                        PieceImage(piece: board[i])
                            .frame(width: cell * 0.9, height: cell * 0.9)
                            .shadow(color: .black.opacity(0.3), radius: cell * 0.035, y: cell * 0.03)
                            .frame(width: cell, height: cell)
                            .offset(x: CGFloat(c) * cell, y: CGFloat(r) * cell)
                            .opacity(!setUp || shown ? 1 : 0)
                            .offset(y: !setUp || shown || reduceMotion ? 0 : -cell * 0.18)
                            .animation(setUp ? .timingCurve(0.23, 1, 0.32, 1, duration: 0.55).delay(0.15 + order * 0.09) : nil, value: shown)
                    }
                }
                if let marks { Canvas { ctx, _ in MarksArt.drawOver(&ctx, marks, cell: cell, flipped: flipped) } }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
        .onAppear { if setUp { DispatchQueue.main.async { shown = true } } }
    }
}

/// Files and ranks, small and quiet, on the board's edge squares: a to h along the bottom, 1 to 8 down the left,
/// in each theme's own colors, turned with the board. A fixed size: they belong to the board, not to the text.
enum Coordinates {
    static func draw(_ ctx: inout GraphicsContext, theme t: BoardTheme, flipped: Bool, side: CGFloat) {
        let cell = side / 8
        let font = Font.custom("Jost-Medium", fixedSize: max(7.5, cell * 0.16))
        let onLight = Color(hex: t.coordinates.on_light).opacity(t.coordinates.opacity)
        let onDark = Color(hex: t.coordinates.on_dark).opacity(t.coordinates.opacity)
        for k in 0..<8 {
            let file = flipped ? 7 - k : k, rank = flipped ? k + 1 : 8 - k
            // The bottom row starts on a dark square and the left column on a light one, whichever way the board faces.
            ctx.draw(Text(String(Square.files[file])).font(font).foregroundColor(k % 2 == 0 ? onDark : onLight),
                     at: CGPoint(x: CGFloat(k + 1) * cell - cell * 0.06, y: side - cell * 0.05), anchor: .bottomTrailing)
            ctx.draw(Text("\(rank)").font(font).foregroundColor(k % 2 == 0 ? onLight : onDark),
                     at: CGPoint(x: cell * 0.06, y: CGFloat(k) * cell + cell * 0.04), anchor: .topLeading)
        }
    }
}
