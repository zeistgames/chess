import Foundation

/// What each side has taken and who is ahead, worked out from a position (board as Square gives it: "wP", "bQ", "").
enum Material {
    static let kinds = ["P", "N", "B", "R", "Q"]
    static let value = ["P": 1, "N": 3, "B": 3, "R": 5, "Q": 9]
    static let start = ["P": 8, "N": 2, "B": 2, "R": 2, "Q": 1]

    static func count(_ side: String, _ board: [String]) -> [String: Int] {
        var c: [String: Int] = [:]
        for p in board where p.count == 2 && p.hasPrefix(side) { c[String(p.suffix(1)), default: 0] += 1 }
        return c
    }

    /// The pieces of `side` no longer on the board, in order pawn, knight, bishop, rook, queen, with how many of each.
    /// A piece beyond the starting count came from a promotion, so it stands for a pawn that is gone but not taken.
    /// `from` is the position the game started from (a game from a set-up position); nil is the usual start.
    static func lost(_ side: String, _ board: [String], from: [String]? = nil) -> [(kind: String, count: Int)] {
        let c = count(side, board)
        let base = from.map { count(side, $0) } ?? start
        let promoted = ["N", "B", "R", "Q"].reduce(0) { $0 + max(0, (c[$1] ?? 0) - (base[$1] ?? 0)) }
        var out: [(String, Int)] = []
        for k in kinds {
            let n = k == "P" ? max(0, (base["P"] ?? 0) - (c["P"] ?? 0) - promoted) : max(0, (base[k] ?? 0) - (c[k] ?? 0))
            if n > 0 { out.append((k, n)) }
        }
        return out
    }

    /// What `side` has captured: the other side's lost pieces.
    static func captured(by side: String, _ board: [String], from: [String]? = nil) -> [(kind: String, count: Int)] {
        lost(side == "w" ? "b" : "w", board, from: from)
    }

    /// White's material minus Black's, in pawns (P 1, N 3, B 3, R 5, Q 9).
    static func balance(_ board: [String]) -> Int {
        board.reduce(0) { sum, p in
            guard p.count == 2, let v = value[String(p.suffix(1))] else { return sum }
            return sum + (p.hasPrefix("w") ? v : -v)
        }
    }

    /// How far `side` is ahead, or 0 when it isn't.
    static func lead(_ side: String, _ board: [String]) -> Int {
        let b = balance(board)
        return max(0, side == "w" ? b : -b)
    }

    /// Whether `side` could still checkmate by some series of legal moves. Used when the other side's flag falls:
    /// without it the game is a draw. A bare king cannot; a king with one bishop or one knight cannot against a bare
    /// king, but can when the other side has anything left to hem its own king in (a pawn, a piece). Anything more
    /// can. (FIDE article 6.9, read conservatively: only the certain draws are draws.)
    static func canMate(_ side: String, _ board: [String]) -> Bool {
        if bishopsOnOneColor(board) { return false }
        let c = count(side, board)
        if (c["P"] ?? 0) + (c["R"] ?? 0) + (c["Q"] ?? 0) > 0 { return true }
        let minors = (c["N"] ?? 0) + (c["B"] ?? 0)
        if minors >= 2 { return true }
        if minors == 0 { return false }
        let them = count(side == "w" ? "b" : "w", board)
        return them.contains { $0.key != "K" && $0.value > 0 }
    }

    /// A dead position: nothing on the board but kings and bishops, and every bishop on squares of one color. No
    /// series of moves can mate then, for either side, however many bishops there are.
    static func bishopsOnOneColor(_ board: [String]) -> Bool {
        var colors = Set<Int>()
        for (i, p) in board.enumerated() where p.count == 2 {
            switch p.suffix(1) {
            case "K": continue
            case "B": colors.insert((i % 8 + i / 8) % 2)
            default: return false
            }
        }
        return colors.count == 1
    }
}

/// A move entered while the engine thinks, played the moment the turn comes if it is legal then.
enum Premove {
    /// Where the piece on `from` could go in some later position: its moves on an open board, captures included.
    static func targets(from: Int, board: [String]) -> Set<Int> {
        guard board.indices.contains(from), board[from].count == 2 else { return [] }
        let side = board[from].prefix(1), kind = board[from].suffix(1)
        let f = from % 8, r = 7 - from / 8 // file 0-7, rank 0-7 from White's side
        var out = Set<Int>()
        func add(_ df: Int, _ dr: Int) {
            let nf = f + df, nr = r + dr
            if (0..<8).contains(nf), (0..<8).contains(nr) { out.insert((7 - nr) * 8 + nf) }
        }
        func rays(_ dirs: [(Int, Int)]) { for (df, dr) in dirs { for k in 1..<8 { add(df * k, dr * k) } } }
        let straight = [(1, 0), (-1, 0), (0, 1), (0, -1)], diagonal = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
        switch kind {
        case "N": for (df, dr) in [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)] { add(df, dr) }
        case "B": rays(diagonal)
        case "R": rays(straight)
        case "Q": rays(straight + diagonal)
        case "K":
            for (df, dr) in straight + diagonal { add(df, dr) }
            if f == 4, r == (side == "w" ? 0 : 7) { add(2, 0); add(-2, 0) }
        case "P":
            let up = side == "w" ? 1 : -1
            add(0, up)
            if r == (side == "w" ? 1 : 6) { add(0, 2 * up) }
            add(1, up); add(-1, up)
        default: break
        }
        return out
    }

    /// The legal move a premove becomes when its turn comes, or nil if it isn't legal now. A pawn reaching the last
    /// rank becomes a queen.
    static func resolve(from: Int, to: Int, legal: [Snapshot.Legal]) -> Snapshot.Legal? {
        let f = Square.name(from), t = Square.name(to)
        let options = legal.filter { $0.from == f && $0.to == t }
        return options.first { $0.promotion == "q" } ?? options.first
    }
}

/// Moves said aloud for VoiceOver: "Knight takes f3, check".
enum Spoken {
    static let names = ["K": "king", "Q": "queen", "R": "rook", "B": "bishop", "N": "knight"]

    static func san(_ san: String) -> String {
        var s = san
        var tail = ""
        if s.hasSuffix("#") { s.removeLast(); tail = ", checkmate" } else if s.hasSuffix("+") { s.removeLast(); tail = ", check" }
        if s.hasPrefix("O-O-O") { return "Castles queenside" + tail }
        if s.hasPrefix("O-O") { return "Castles kingside" + tail }
        var promo = ""
        if let eq = s.firstIndex(of: "=") {
            promo = ", promotes to \(names[String(s[s.index(after: eq)...].prefix(1))] ?? "a piece")"
            s = String(s[..<eq])
        }
        var piece = "pawn"
        if let first = s.first, let n = names[String(first)] { piece = n; s.removeFirst() }
        let takes = s.contains("x")
        let dest = String(s.suffix(2))
        let from = String(s.replacingOccurrences(of: "x", with: "").dropLast(2))
        let who = from.isEmpty ? piece : "\(piece) from \(from)"
        let line = "\(who) \(takes ? "takes" : "to") \(dest)\(promo)\(tail)"
        return line.prefix(1).uppercased() + line.dropFirst()
    }
}
