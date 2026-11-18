import SwiftUI

/// A board theme, read from core/board-themes.json: the same file the web and the main Zeist app can read.
struct BoardTheme: Codable, Identifiable, Hashable, Sendable {
    struct Coordinates: Codable, Hashable, Sendable { var on_light: String; var on_dark: String; var opacity: Double }
    struct Grain: Codable, Hashable, Sendable {
        var lines: Int
        var color: String?
        var opacity: Double?
        var wave: Double?
        var width: Double?
        var direction: String?
        var seed: Int?
        var sheen: Double?
        var bands: Int?
        var band_opacity: Double?
    }
    struct Marks: Codable, Hashable, Sendable {
        var last: String; var last_from: Double; var last_to: Double; var last_outline: Double
        var selected: String; var selected_opacity: Double
        var hint: String; var hint_opacity: Double
        var check: String
    }
    var id: String
    var name: String
    var light: String
    var dark: String
    var coordinates: Coordinates
    var grain: Grain
    var marks: Marks
}

enum Themes {
    struct File: Codable { var `default`: String; var themes: [BoardTheme] }

    static let file: File = {
        let url = Places.core.appending(path: "board-themes.json")
        if let d = try? Data(contentsOf: url), let f = try? JSONDecoder().decode(File.self, from: d), !f.themes.isEmpty { return f }
        return File(default: "slate", themes: [fallback])
    }()

    static var all: [BoardTheme] { file.themes }

    static func named(_ id: String?) -> BoardTheme {
        all.first { $0.id == id } ?? all.first { $0.id == file.default } ?? all[0]
    }

    /// Used only if the file is missing from the app.
    static let fallback = BoardTheme(id: "slate", name: "Slate", light: "#838e9b", dark: "#687686",
                                     coordinates: .init(on_light: "#3b4350", on_dark: "#d6dbe2", opacity: 0.6),
                                     grain: .init(lines: 0, sheen: 0.06),
                                     marks: .init(last: "#f2e2b0", last_from: 0.3, last_to: 0.44, last_outline: 0, selected: "#f4f1ea",
                                                  selected_opacity: 0.22, hint: "#12110e", hint_opacity: 0.32, check: "#ff7442"))
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt64(s, radix: 16) ?? 0
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// The squares and their grain. Drawn only when the theme or size changes, never on a move.
struct BoardGround: View, Equatable {
    let theme: BoardTheme
    var flipped = false

    var body: some View {
        Canvas { ctx, size in
            let side = min(size.width, size.height), cell = side / 8
            let light = Color(hex: theme.light), dark = Color(hex: theme.dark)
            for i in 0..<64 {
                let (c, r) = flipped ? (7 - i % 8, 7 - i / 8) : (i % 8, i / 8)
                let rect = CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: cell, height: cell)
                let isLight = (i / 8 + i % 8) % 2 == 0
                ctx.fill(Path(rect), with: .color(isLight ? light : dark))
                if theme.grain.lines > 0 { grain(&ctx, rect, square: i, light: isLight) }
            }
            let sheen = theme.grain.sheen ?? 0.05
            ctx.fill(Path(CGRect(x: 0, y: 0, width: side, height: side)),
                     with: .linearGradient(Gradient(colors: [.white.opacity(sheen), .clear, .black.opacity(sheen * 1.3)]),
                                           startPoint: .zero, endPoint: CGPoint(x: side * 0.6, y: side)))
        }
        .accessibilityHidden(true)
    }

    /// Fine, nearly parallel lines that drift slowly, over a few soft streaks: the grain of a cut board.
    /// Repeatable from the theme's seed.
    private func grain(_ ctx: inout GraphicsContext, _ rect: CGRect, square: Int, light: Bool) {
        let g = theme.grain
        var rng = Seeded(UInt64((g.seed ?? 1) * 7919 + square * 104_729 + 1))
        let across = g.direction == "alternate" && !light
        let len = across ? rect.height : rect.width, breadth = across ? rect.width : rect.height
        let color = Color(hex: g.color ?? "#000000")
        var inner = ctx
        inner.clip(to: Path(rect))
        func line(at base: CGFloat, drift: CGFloat, amp: CGFloat, freq: CGFloat, phase: CGFloat) -> Path {
            var p = Path()
            let steps = 16
            for s in 0...steps {
                let t = CGFloat(s) / CGFloat(steps)
                let at = base + drift * t + sin(t * .pi * 2 * freq + phase) * amp
                let pt = across ? CGPoint(x: rect.minX + at, y: rect.minY + t * len) : CGPoint(x: rect.minX + t * len, y: rect.minY + at)
                s == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            return p
        }
        let phase = rng.next() * .pi * 2
        let freq = 0.35 + rng.next() * 0.45
        let drift = (rng.next() - 0.5) * breadth * 0.18
        // Soft streaks first.
        for _ in 0..<(g.bands ?? 0) {
            let w = breadth * (0.06 + rng.next() * 0.14)
            inner.stroke(line(at: rng.next() * breadth, drift: drift, amp: breadth * 0.03, freq: freq, phase: phase),
                         with: .color(color.opacity((g.band_opacity ?? 0.05) * (0.5 + rng.next()))), lineWidth: w)
        }
        let n = max(1, g.lines)
        let gap = breadth / CGFloat(n)
        let amp = CGFloat(g.wave ?? 0.5) * gap
        for k in -1...n {
            let base = (CGFloat(k) + 0.2 + rng.next() * 0.6) * gap
            let w = CGFloat(g.width ?? 0.007) * rect.width * (0.5 + rng.next() * 1.1)
            inner.stroke(line(at: base, drift: drift, amp: amp * (0.7 + rng.next() * 0.6), freq: freq, phase: phase + rng.next() * 0.5),
                         with: .color(color.opacity((g.opacity ?? 0.1) * (0.35 + rng.next() * 1.0))), lineWidth: max(0.35, w))
        }
    }
}

/// A small, repeatable random sequence.
struct Seeded {
    private var s: UInt64
    init(_ seed: UInt64) { s = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func next() -> CGFloat {
        s ^= s << 13; s ^= s >> 7; s ^= s << 17
        return CGFloat(s % 1_000_000) / 1_000_000
    }
}

/// A piece set, read from core/piece-sets.json. Sets differ in shape only: all are ivory and ebony (ios/scripts/pieces.py).
struct PieceSet: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var author: String
    var license: String
    var source: String
}

enum PieceSets {
    struct File: Codable { var `default`: String; var sets: [PieceSet] }

    static let file: File = {
        let url = Places.core.appending(path: "piece-sets.json")
        if let d = try? Data(contentsOf: url), let f = try? JSONDecoder().decode(File.self, from: d), !f.sets.isEmpty { return f }
        return File(default: fallback.id, sets: [fallback])
    }()

    static var all: [PieceSet] { file.sets }

    static func named(_ id: String?) -> PieceSet {
        all.first { $0.id == id } ?? all.first { $0.id == file.default } ?? all[0]
    }

    /// Used only if the file is missing from the app.
    static let fallback = PieceSet(id: "zeist", name: "Zeist", author: "Amrith", license: "AGPL-3.0-or-later",
                                   source: "https://zeist.gg")

    /// The image for a piece ("wK", "bN") in a set, from the asset catalog.
    static func image(_ piece: String, set: String) -> String { "\(named(set).id)/\(piece.prefix(1))\(piece.suffix(1))" }
}

/// The board theme and piece set the player chose in Settings.
enum Look {
    static let key = "board.theme"
    static let piecesKey = "board.pieces"
    /// Files and ranks drawn on the board's edge squares. On by default.
    static let coordinatesKey = "board.coordinates"
    /// The game's board spans the screen with square corners. Off by default: Zeist's inset board.
    static let edgeKey = "board.edge"
    static var theme: BoardTheme { Themes.named(UserDefaults.standard.string(forKey: key)) }
    static var pieces: PieceSet { PieceSets.named(UserDefaults.standard.string(forKey: piecesKey)) }
}
