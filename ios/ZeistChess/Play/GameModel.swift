import Foundation
import Observation

/// The position as core/rules.js describes it (Game.snapshot()).
struct Snapshot: Codable, Equatable, Sendable {
    struct Legal: Codable, Equatable, Sendable {
        var uci: String; var from: String; var to: String; var san: String
        var capture: Bool; var promotion: String?; var castle: String?
    }
    struct Outcome: Codable, Equatable, Sendable { var result: String; var reason: String; var winner: String? }
    var fen: String
    var turn: String
    var board: [String]
    var legal: [Legal]
    var check: String?
    var last: String?
    var moves: [String]
    var san: [String]
    var outcome: Outcome?
}

/// Squares: index 0 is a8, 63 is h1, row by row, as core/rules.js gives the board.
enum Square {
    static let files = Array("abcdefgh")
    static func name(_ i: Int) -> String { "\(files[i % 8])\(8 - i / 8)" }
    static func index(_ s: some StringProtocol) -> Int? {
        let c = Array(s)
        guard c.count == 2, let f = files.firstIndex(of: c[0]), let r = c[1].wholeNumberValue, (1...8).contains(r) else { return nil }
        return (8 - r) * 8 + f
    }
    /// The board from a FEN's first field, for drawing a position without the rules.
    static func board(fromFEN fen: String) -> [String] {
        var out: [String] = []
        for ch in fen.split(separator: " ").first ?? "" {
            if ch == "/" { continue }
            if let n = ch.wholeNumberValue { out += Array(repeating: "", count: n) }
            else { out.append((ch.isUppercase ? "w" : "b") + ch.uppercased()) }
        }
        return out.count == 64 ? out : Array(repeating: "", count: 64)
    }
}

/// A game against an engine: the moves, the engine's turn, undo, resign, the end and the log.
@MainActor @Observable
final class GameModel {
    private(set) var record: GameRecord
    let engine: Engine
    private(set) var snap: Snapshot
    /// Each square's piece identity, so a piece glides when it moves instead of jumping.
    private(set) var ids: [Int?] = Array(repeating: nil, count: 64)
    private(set) var thinking = false
    /// The engine couldn't answer (after a retry). Shown under the board with a way to try again.
    /// Each of these is the app or the engine failing, never the player's slip, so it counts as trouble for ReviewRequest.
    private(set) var trouble: String? { didSet { if trouble != nil { ReviewRequest.shared.record(.trouble) } } }
    var selected: Int?
    /// A pawn reached the last rank: which promotion to choose, from and to.
    var promoting: (from: Int, to: Int)?
    /// Bumped when the engine moves, so the board can tell the engine's moves from yours.
    private(set) var engineMoves = 0
    private var request = 0
    private var nextID = 0
    private var busy = false

    /// The clocks, in a game that has them.
    private(set) var clock: ChessClock?
    private var clockTask: Task<Void, Never>?
    private var warnedLow = false
    /// A move entered while the engine thinks (timed games): played the moment the turn comes, if legal then.
    private(set) var premove: (from: Int, to: Int)?
    /// The move being looked at while stepping through the game; nil for the live position.
    private(set) var viewPly: Int?
    /// The position (FEN) after each move; positions[0] is the start.
    private(set) var positions: [String] = []
    /// The board turned the other way, by the player's choice.
    var flipped = false
    /// The engine's own evaluation after each of its searches, in centipawns from its side (mates as ±10000).
    private(set) var evals: [Int] = []
    /// A quiet line for a moment: a declined draw.
    private(set) var notice: String?
    /// Moves played when the engine last declined a draw; another offer waits ten moves.
    private var declinedAt: Int?
    /// A suggested move, shown as a soft arrow until the next move.
    private(set) var hint: (from: Int, to: Int)?
    private(set) var hinting = false

    /// The engine's search, replaceable in tests.
    var think: @MainActor ([String: Any]) async throws -> Any = { try await Core.shared.call("think", $0) }

    /// Settings keys for play.
    static let queenKey = "play.autoQueen", paceKey = "play.pace"

    var player: String { record.player }
    var playerIsWhite: Bool { record.player == "w" }
    var over: Bool { record.finished }
    var myTurn: Bool { !over && snap.turn == record.player && !thinking && viewPly == nil }
    var timed: Bool { record.timeControl != nil }
    /// Undo takes back your last move (and the engine's answer). Timed games have no Undo.
    var canUndo: Bool { !timed && !rated && !over && record.moves.count >= (record.player == "w" ? 1 : 2) && !busy }
    /// A rated game: no undo, hints or draw offers, and the engine never resigns or asks for a draw. It plays to its
    /// end on the board or a resignation, which is what Zeist checks.
    var rated: Bool { record.isRated }
    /// While the engine thinks in a timed game, the player may enter one move ahead.
    var canPremove: Bool { timed && !over && snap.turn != record.player && viewPly == nil }
    /// The board drawn from White's side unless the player is Black, turned when the player flips it.
    var whiteAtBottom: Bool { playerIsWhite != flipped }
    /// Hints are for games without a clock, on your turn.
    var canHint: Bool { !timed && !rated && myTurn && !hinting }
    var canOfferDraw: Bool { !over && !rated && declinedAt.map { record.moves.count >= $0 + 10 } ?? true }

    /// The time for a steady clock: seconds since the phone started, unaffected by changes to the time of day.
    static func now() -> Double { ProcessInfo.processInfo.systemUptime }

    init(record: GameRecord, engine: Engine) {
        self.record = record
        self.engine = engine
        let board = Square.board(fromFEN: record.fen)
        snap = Snapshot(fen: record.fen, turn: record.fen.split(separator: " ").dropFirst().first.map(String.init) ?? "w",
                        board: board, legal: [], check: nil, last: record.moves.last, moves: record.moves, san: record.san, outcome: nil)
        resetIDs()
        if let tc = record.timeControl {
            let left = record.clockLeft ?? [tc.base * 1000, tc.base * 1000]
            let turn = snap.turn
            clock = ChessClock(control: tc, white: Double(left[0]) / 1000, black: Double(left[1]) / 1000,
                               running: record.finished || record.moves.isEmpty ? nil : turn, paused: true)
        }
    }

    /// Starts a game: picks the seed, asks core for the engine's settings at the level, and saves it.
    static func begin(engine: Engine, player: String, level: Int, adaptive: Bool, rating: Int? = nil, time: TimeControl? = nil,
                      start: String = GameModel.standardStart, learn: Bool = false) async throws -> GameModel {
        if let old = GameLog.shared.current { Self.leaveForGood(old) }
        ReviewRequest.shared.movedOn()
        let seed = UInt32.random(in: 1...UInt32.max)
        let rating = adaptive ? nil : rating.flatMap { r in engine.manifest.ratings.map { min($0.upperBound, max($0.lowerBound, r)) } }
        var ask: [String: Any] = ["manifest": engine.coreArgs["manifest"]!, "level": level, "seed": seed]
        if let rating { ask["rating"] = rating }
        let settings = try await Core.shared.call("settings", ask)
        let level = ((settings as? [String: Any])?["level"] as? NSNumber)?.intValue ?? level
        var rec = GameRecord(startFEN: start, fen: start, player: player, engineID: engine.id, engineName: engine.name,
                             engineVersion: engine.manifest.version, packSHA: engine.packSHA, level: level, adaptive: adaptive, rating: rating,
                             engineSettings: Self.json(settings), seed: seed, appVersion: GameRecord.appVersion)
        if let time {
            rec.timeControl = time
            rec.timeClass = time.kind.rawValue
            rec.clocks = []
            rec.clockLeft = [time.base * 1000, time.base * 1000]
        }
        if learn { rec.learn = true }
        GameLog.shared.save(rec)
        let m = GameModel(record: rec, engine: engine)
        Measure.gameStarted(engine: engine.id, adaptive: adaptive, rating: rating != nil, level: level, clock: time?.name, side: player)
        _ = try? await Core.shared.call("newGame", ["engine": engine.coreArgs])
        return m
    }

    /// A rated game against the Zeist engine: Zeist starts it and gives the level (level nil: Matched), the seed and
    /// the side (seat nil: Zeist picks). Always from the usual start, without a clock.
    static func beginRated(engine: Engine, level: Int?, seat: Int?) async throws -> GameModel {
        guard engine.id == Rated.engineID, let who = Rated.who() else { throw Rated.Failure(status: 401, error: "signin") }
        let before = await RatingBook.shared.refresh()?.rating ?? RatingBook.shared.current?.rating
        let g = try await Rated.start(level: level, seat: seat)
        // Kept at once, before anything else can fail: the game exists on Zeist from here. Without saved settings the
        // engine's settings come from the level and the seed (core's think), which are the same.
        if let old = GameLog.shared.current { leaveForGood(old) }
        var rec = GameRecord(startFEN: standardStart, fen: standardStart, player: g.seat == 0 ? "w" : "b", engineID: engine.id, engineName: engine.name,
                             engineVersion: engine.manifest.version, packSHA: engine.packSHA, level: g.level, adaptive: false, rating: nil,
                             engineSettings: nil, seed: g.seed, appVersion: GameRecord.appVersion)
        rec.ratedID = g.id
        rec.ratedBy = who.owner
        rec.matched = level == nil
        rec.ratingBefore = before
        GameLog.shared.save(rec)
        ReviewRequest.shared.movedOn()
        if let settings = try? await Core.shared.call("settings", ["manifest": engine.coreArgs["manifest"]!, "level": g.level, "seed": g.seed]) {
            rec.engineSettings = json(settings)
            GameLog.shared.save(rec)
        }
        let m = GameModel(record: rec, engine: engine)
        Measure.gameStarted(engine: engine.id, adaptive: false, rating: false, level: g.level, clock: nil, side: rec.player)
        _ = try? await Core.shared.call("newGame", ["engine": engine.coreArgs])
        return m
    }

    /// The game in progress, left for another: an unrated one is kept as unfinished; a rated one is resigned, since
    /// Zeist would count it as a loss a day later anyway.
    static func leaveForGood(_ old: GameRecord) {
        guard old.isRated, let id = old.ratedID, let by = old.ratedBy else { GameLog.shared.abandon(old.id); return }
        var r = old
        r.result = r.player == "w" ? "0-1" : "1-0"
        r.ending = "resigned"
        r.endedAt = Date()
        GameLog.shared.save(r)
        // What comes of it is written to the log by RatedFinishes once Zeist answers.
        Task { _ = await RatedFinishes.send(id, moves: r.moves, resign: true, owner: by) }
    }

    static let standardStart = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    private static func json(_ any: Any) -> JSONValue? {
        guard let d = try? JSONSerialization.data(withJSONObject: any, options: [.fragmentsAllowed]) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: d)
    }

    private var settingsAny: Any { record.engineSettings?.any ?? NSNull() }

    /// Reads the position from core (on open, and after the web view restarts), then lets the engine move if due.
    func resume() async {
        do {
            let s = try await Core.shared.decode(Snapshot.self, "state", ["fen": record.startFEN, "moves": record.moves])
            snap = s
            resetIDs()
            await refreshPositions()
            if record.openingName == nil { nameOpening() }
            if s.outcome != nil, !over { finish(s.outcome!) }
            else if rated, !over, s.moves.count >= Self.moveLimit { finish(Snapshot.Outcome(result: "1/2-1/2", reason: "move-limit", winner: nil)) }
            resumeClock()
            engineIfDue()
        } catch {
            trouble = "The board couldn't be set up. Try again."
        }
    }

    private func refreshPositions() async {
        if let v = try? await Core.shared.call("replay", ["fen": record.startFEN, "moves": record.moves]) as? [String: Any],
           let f = v["fens"] as? [String], f.count == record.moves.count + 1 { positions = f }
        else { positions = [record.startFEN] + Array(repeating: "", count: record.moves.count) }
    }

    private func resetIDs() {
        ids = snap.board.map { $0.isEmpty ? nil : { nextID += 1; return nextID }() }
    }

    // MARK: Your moves

    func legal(from i: Int) -> [Snapshot.Legal] {
        guard myTurn else { return [] }
        let name = Square.name(i)
        return snap.legal.filter { $0.from == name }
    }

    /// Where the selected piece may go: its legal moves on your turn, its premove squares while the engine thinks.
    func hints(from i: Int) -> [(to: Int, capture: Bool)] {
        if canPremove { return Premove.targets(from: i, board: snap.board).sorted().map { ($0, false) } }
        let list = legal(from: i)
        return Set(list.map(\.to)).sorted().compactMap { name in
            Square.index(name).map { t in (t, !snap.board[t].isEmpty || list.contains { $0.to == name && $0.capture }) }
        }
    }

    func isMine(_ i: Int) -> Bool { snap.board[i].hasPrefix(record.player) }

    /// Whether a piece on this square can be picked up now: on your turn, or to premove.
    func canLift(_ i: Int) -> Bool { isMine(i) && (myTurn || canPremove) }

    /// A tap on a square: select your piece, move the selected one, or let go. While looking back, back to the game.
    func tap(_ i: Int) {
        if viewPly != nil { step(to: nil); return }
        guard !over else { return }
        if canPremove {
            if premove != nil { premove = nil; selected = nil; Feel.shared.select(); return }
            if let s = selected, s != i, Premove.targets(from: s, board: snap.board).contains(i) {
                premove = (s, i); selected = nil; Feel.shared.select(); return
            }
            if isMine(i), selected != i { selected = i; Feel.shared.select() } else { selected = nil }
            return
        }
        if let s = selected {
            if s == i { selected = nil; return }
            if legal(from: s).contains(where: { $0.to == Square.name(i) }) { try_(from: s, to: i); return }
        }
        if isMine(i) && myTurn {
            selected = i
            Feel.shared.select()
        } else {
            if selected != nil || (myTurn && !snap.board[i].isEmpty) { Feel.shared.refuse() }
            selected = nil
        }
    }

    /// A piece dragged from one square and let go on another.
    func drop(from: Int, to: Int) {
        guard from != to else { return }
        if canPremove {
            if Premove.targets(from: from, board: snap.board).contains(to) { premove = (from, to); selected = nil; Feel.shared.select() }
            return
        }
        if legal(from: from).contains(where: { $0.to == Square.name(to) }) { try_(from: from, to: to) } else {
            Feel.shared.refuse()
        }
    }

    private func try_(from: Int, to: Int) {
        let options = legal(from: from).filter { $0.to == Square.name(to) }
        guard let first = options.first else { return }
        selected = nil
        if options.count > 1 {
            // "Always promote to a queen": no choice to make.
            if UserDefaults.standard.bool(forKey: Self.queenKey), let q = options.first(where: { $0.promotion == "q" }) {
                Task { await play(q.uci, byEngine: false) }
                return
            }
            promoting = (from, to); return
        }
        Task { await play(first.uci, byEngine: false) }
    }

    func promote(_ piece: String) {
        guard let p = promoting else { return }
        promoting = nil
        Task { await play(Square.name(p.from) + Square.name(p.to) + piece, byEngine: false) }
    }

    private func play(_ uci: String, byEngine: Bool) async {
        guard (!busy || byEngine), !over else { return }
        // A move from a side whose time has already run out is not played: its flag falls instead.
        if let c = clock, let side = c.flagged(at: Self.now()), side == snap.turn { flag(side); return }
        busy = true
        defer { busy = false }
        let capture = snap.legal.first { $0.uci == uci }?.capture ?? false
        let before = snap
        let clockBefore = clock
        // The clock is pressed the moment the move is made.
        let left = press(snap.turn)
        if byEngine { viewPly = nil } else { drawOffered = false }
        hint = nil
        notice = nil
        // Show the move at once; the rules confirm it a moment later.
        optimistic(uci)
        do {
            let s = try await Core.shared.decode(Snapshot.self, "play", ["fen": record.startFEN, "moves": record.moves, "move": uci])
            guard !over else { return }
            if let left { record.clocks = (record.clocks ?? []) + [left] }
            commit(s, from: before)
            if byEngine { engineMoves += 1; Feel.shared.reply(capture: capture) } else { Feel.shared.move(capture: capture) }
            if s.check != nil, s.outcome == nil { Feel.shared.check() }
            if let o = s.outcome { finish(o) }
            else if rated, s.moves.count >= Self.moveLimit { finish(Snapshot.Outcome(result: "1/2-1/2", reason: "move-limit", winner: nil)) }
            else if !byEngine { engineIfDue() }
        } catch {
            guard !over else { return }
            snap = before
            clock = clockBefore
            watchClock()
            resetIDs()
            trouble = "That move couldn't be played. Try again."
        }
    }

    // MARK: The clock

    /// Presses the clock for the side that just moved. Returns its time left in milliseconds, for the log.
    private func press(_ side: String) -> Int? {
        guard var c = clock else { return nil }
        let now = Self.now()
        c.moved(side, at: now)
        clock = c
        if side == record.player { warnedLow = c.remaining(side, at: now) <= c.control.lowTime ? warnedLow : false }
        saveClock()
        watchClock()
        return Int((c.remaining(side, at: now) * 1000).rounded())
    }

    private func saveClock() {
        guard let c = clock else { return }
        let now = Self.now()
        record.clockLeft = [Int((c.remaining("w", at: now) * 1000).rounded()), Int((c.remaining("b", at: now) * 1000).rounded())]
    }

    /// Waits for the running side's flag (and, for the player, the moment time runs low).
    private func watchClock() {
        clockTask?.cancel()
        guard let c = clock, !over, !c.paused, c.running != nil else { return }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let c = self.clock, !self.over, let side = c.running, !c.paused else { return }
                let left = c.remaining(side, at: Self.now())
                if left <= 0 { self.flag(side); return }
                var wait = min(left, 1)
                if side == self.record.player, !self.warnedLow {
                    if left <= c.control.lowTime { self.warnedLow = true; Feel.shared.lowTime() } else { wait = min(wait, left - c.control.lowTime) }
                }
                try? await Task.sleep(for: .seconds(wait + 0.002))
            }
        }
    }

    /// A flag fell: a loss on time, or a draw if the other side has nothing to checkmate with.
    private func flag(_ side: String) {
        guard !over else { return }
        request += 1
        if thinking { thinking = false; Task { _ = try? await Core.shared.call("stop") } }
        premove = nil
        let other = side == "w" ? "b" : "w"
        if Material.canMate(other, snap.board) {
            finish(Snapshot.Outcome(result: other == "w" ? "1-0" : "0-1", reason: "timeout", winner: other))
        } else {
            finish(Snapshot.Outcome(result: "1/2-1/2", reason: "timeout-insufficient", winner: nil))
        }
    }

    /// The app went to the background or the screen was left: the clocks stop, the search ends, the game is saved.
    func pauseClock() {
        guard var c = clock, !over, !c.paused else { return }
        c.pause(at: Self.now())
        clock = c
        clockTask?.cancel()
        if thinking { request += 1; thinking = false; Task { _ = try? await Core.shared.call("stop") } }
        saveClock()
        GameLog.shared.save(record)
    }

    /// Back to the game: the clocks run again.
    func resumeClock() {
        guard var c = clock, !over, c.paused else { return }
        c.resume(at: Self.now())
        clock = c
        watchClock()
    }

    /// Time left for a side, now.
    func timeLeft(_ side: String, at now: Double = GameModel.now()) -> Double? { clock?.remaining(side, at: now) }

    // MARK: Going through the moves

    /// Shows the position after `ply` moves; nil (or the last move) is the live position.
    func step(to ply: Int?) {
        let n = record.moves.count
        let target = ply.map { max(0, min(n, $0)) }
        let next = target == n ? nil : target
        guard next != viewPly else { return }
        if next != nil, positions.count != n + 1 || positions.contains("") { Task { await refreshPositions() } }
        viewPly = next
        selected = nil
        Feel.shared.select()
    }

    func stepBack() { step(to: shownPly - 1) }
    func stepForward() { step(to: shownPly + 1) }

    /// The move count of the position shown.
    var shownPly: Int { viewPly ?? record.moves.count }

    /// The board shown: the live one, or the one being looked at.
    var shownBoard: [String] {
        guard let p = viewPly, positions.indices.contains(p), !positions[p].isEmpty else { return snap.board }
        return Square.board(fromFEN: positions[p])
    }

    /// The board the game started from, for counting captures; nil for the usual start.
    var startBoard: [String]? {
        #if DEBUG
        if Debug.args.contains("-standard-captures") { return nil }
        #endif
        return record.startFEN == Self.standardStart ? nil : Square.board(fromFEN: record.startFEN)
    }

    var shownLast: String? {
        guard let p = viewPly else { return snap.last }
        return p > 0 && record.moves.indices.contains(p - 1) ? record.moves[p - 1] : nil
    }

    /// Moves the piece on the board before the rules answer, carrying its identity so it glides.
    private func optimistic(_ uci: String) {
        let c = Array(uci)
        guard c.count >= 4, let f = Square.index(String(c[0...1])), let t = Square.index(String(c[2...3])) else { return }
        var b = snap.board
        var ids = self.ids
        let piece = b[f]
        // En passant: a pawn moving diagonally to an empty square takes the pawn beside it.
        if piece.hasSuffix("P"), f % 8 != t % 8, b[t].isEmpty {
            let taken = t + (piece.hasPrefix("w") ? 8 : -8)
            if (0..<64).contains(taken) { b[taken] = ""; ids[taken] = nil }
        }
        // Castling: the rook comes across.
        if piece.hasSuffix("K"), abs(f % 8 - t % 8) == 2 {
            let (rf, rt) = t % 8 == 6 ? (t + 1, t - 1) : (t - 2, t + 1)
            b[rt] = b[rf]; b[rf] = ""; ids[rt] = ids[rf]; ids[rf] = nil
        }
        b[t] = c.count == 5 ? String(piece.prefix(1)) + String(c[4]).uppercased() : piece
        b[f] = ""
        ids[t] = ids[f]; ids[f] = nil
        snap.board = b
        snap.last = uci
        snap.legal = []
        snap.check = nil
        self.ids = ids
    }

    private func commit(_ s: Snapshot, from before: Snapshot) {
        snap = s
        // Keep identities where the optimistic board agrees; new ones elsewhere.
        for i in 0..<64 {
            if s.board[i].isEmpty { ids[i] = nil } else if ids[i] == nil { nextID += 1; ids[i] = nextID }
        }
        if positions.count == s.moves.count { positions.append(s.fen) }
        record.moves = s.moves
        record.san = s.san
        record.fen = s.fen
        trouble = nil
        GameLog.shared.save(record)
        nameOpening()
    }

    /// Looks the opening up while the game is young. A game that leaves the book keeps its last name.
    private func nameOpening() {
        guard record.moves.count <= 40 else { return }
        let moves = record.moves, start = record.startFEN
        Task {
            guard let v = try? await Core.shared.call("opening", ["fen": start, "moves": moves]) as? [String: Any],
                  let name = v["name"] as? String, let eco = v["eco"] as? String, record.moves == moves else { return }
            if record.openingName != name {
                record.openingName = name
                record.openingECO = eco
                GameLog.shared.save(record)
            }
        }
    }

    /// The opening's name, shown under the moves during the first moves of a game.
    var openingLine: String? { record.moves.count <= 24 ? record.openingName : nil }

    // MARK: The engine's moves

    private func engineIfDue() {
        guard !over, snap.turn != record.player, !thinking else { return }
        #if DEBUG
        if Debug.args.contains("-freeze") { thinking = true; return }
        #endif
        thinking = true
        trouble = nil
        request += 1
        let id = request
        let began = Date()
        Task {
            defer { if id == request { thinking = false } }
            var attempts = 0
            while true {
                attempts += 1
                do {
                    var args: [String: Any] = ["engine": engine.coreArgs, "fen": record.startFEN, "moves": record.moves,
                                               "settings": settingsAny, "level": record.level, "seed": record.seed]
                    if let c = clock {
                        let now = Self.now(), inc = c.control.increment * 1000
                        args["clock"] = ["wtime": Int(c.remaining("w", at: now) * 1000), "btime": Int(c.remaining("b", at: now) * 1000), "winc": inc, "binc": inc]
                    }
                    let v = try await think(args)
                    guard id == request, let move = (v as? [String: Any])?["move"] as? String else { return }
                    if let e = Self.evaluation(v) { evals.append(e) }
                    if !rated, Self.gaveUp(evals, humanMode: UserDefaults.standard.bool(forKey: Self.humanKey)) {
                        thinking = false
                        let winner = record.player
                        finish(Snapshot.Outcome(result: winner == "w" ? "1-0" : "0-1", reason: "engine-resigned", winner: winner))
                        return
                    }
                    // The engine takes its time like a person would (core's levels.pace), on its own clock in a timed
                    // game. With instant replies chosen: a beat with no clock, nothing with one.
                    let natural = UserDefaults.standard.object(forKey: Self.paceKey) == nil || UserDefaults.standard.bool(forKey: Self.paceKey)
                    let pace = ((v as? [String: Any])?["pace"] as? NSNumber)?.doubleValue
                    let total = natural && pace != nil ? pace! / 1000 : (timed ? 0 : 0.45)
                    let wait = total - Date().timeIntervalSince(began)
                    if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                    guard id == request, !over else { return }
                    thinking = false
                    await play(move, byEngine: true)
                    // Asked once a game (kept with the game, so a relaunch doesn't ask again), and not while a
                    // premove waits: that would answer it unseen, so it asks after a later move instead.
                    if !over, premove == nil, !rated,
                       Self.asksForDraw(evals, humanMode: UserDefaults.standard.bool(forKey: Self.humanKey), asked: record.engineAskedDraw == true) {
                        record.engineAskedDraw = true
                        GameLog.shared.save(record)
                        drawOffered = true
                    }
                    await playPremove()
                    return
                } catch CoreError.stale {
                    return
                } catch CoreError.outOfTime {
                    guard id == request else { return }
                    // With a clock running, its flag is about to fall and the clock ends the game. Before the first
                    // move no clock runs: no flag will fall, so try once more, then offer Try again.
                    if clock?.running != nil, clock?.paused == false { return }
                    if attempts < 2 { continue }
                    trouble = "\(engine.name) couldn't find a move in time. Try again."
                    return
                } catch {
                    guard id == request else { return }
                    if attempts < 2 { continue }
                    // A worker that crashed, ran out of memory, or took its web view down with it: say so calmly,
                    // keep the board as it was, and offer Try again, Resign and the way Home.
                    trouble = "\(engine.name) stopped before it could move, perhaps for lack of memory. Try again, or play a smaller engine."
                    return
                }
            }
        }
    }

    /// The engine's score for its best line, from its own side: centipawns, or ±10000 for a mate.
    static func evaluation(_ v: Any) -> Int? {
        guard let lines = (v as? [String: Any])?["lines"] as? [[String: Any]], let best = lines.first else { return nil }
        if let m = (best["mate"] as? NSNumber)?.intValue { return m > 0 ? 10000 : -10000 }
        return (best["cp"] as? NSNumber)?.intValue
    }

    /// Human mode (Settings, off unless the player turns it on): a beaten engine behaves as a person might. Well
    /// behind (about a rook down in three of its last five searches) it asks for a draw, once a game; truly beaten
    /// (about a queen down or worse in five of its last seven) it resigns. Without human mode an engine plays every game to the end.
    static let humanKey = "play.humanMode"
    static let resignAt = -900, resignAfter = 5, resignWithin = 7
    static let drawAt = -500, drawAfter = 3, drawWithin = 5
    /// Whether the engine has seen itself this far behind often enough lately: its latest search says so, and so do
    /// `after` of its last `within` searches that said anything.
    /// A score of exactly zero says nothing: it is the engine's score for a draw, and a short search now and then
    /// gives it to a position that is plainly lost (Stockfish Lite at a low level did so on three of eight moves
    /// while down by nearly everything, 2026-11-19). A strict run of losing scores was broken by each of those, so
    /// a beaten engine asked and resigned only some of the time. Such searches are left out of the count, and the
    /// engine never acts on one: the latest search must itself see the game as lost.
    static func beaten(_ evals: [Int], at: Int, after: Int, within: Int) -> Bool {
        guard let last = evals.last, last <= at else { return false }
        return evals.filter { $0 != 0 }.suffix(within).filter { $0 <= at }.count >= after
    }
    static func asksForDraw(_ evals: [Int], humanMode: Bool, asked: Bool) -> Bool {
        guard humanMode, !asked else { return false }
        return beaten(evals, at: drawAt, after: drawAfter, within: drawWithin)
    }
    /// The engine has asked for a draw and waits on the player: Accept, Decline, or simply the next move.
    private(set) var drawOffered = false

    func acceptDraw() {
        guard drawOffered, !over else { return }
        drawOffered = false
        request += 1
        premove = nil
        finish(Snapshot.Outcome(result: "1/2-1/2", reason: "agreement", winner: nil))
    }

    func declineDraw() {
        guard drawOffered else { return }
        drawOffered = false
        Feel.shared.select()
    }

    static func gaveUp(_ evals: [Int], humanMode: Bool) -> Bool {
        guard humanMode else { return false }
        return beaten(evals, at: resignAt, after: resignAfter, within: resignWithin)
    }

    /// Half-moves since the very start of the game, counting those before a chosen start position (from its FEN).
    var gamePly: Int {
        let f = record.startFEN.split(separator: " ")
        let full = f.count >= 6 ? Int(f[5]) ?? 1 : 1
        return (full - 1) * 2 + (f.count >= 2 && f[1] == "b" ? 1 : 0) + record.moves.count
    }

    /// The player offers a draw. The engine takes it when its own evaluation is about level or worse for it and the
    /// game is past the opening; otherwise it says no, once, quietly.
    func offerDraw() {
        guard !over, canOfferDraw else { return }
        let past = gamePly >= 30
        if past, let e = evals.last, e <= 30 {
            request += 1
            if thinking { thinking = false; Task { _ = try? await Core.shared.call("stop") } }
            premove = nil
            finish(Snapshot.Outcome(result: "1/2-1/2", reason: "agreement", winner: nil))
        } else {
            declinedAt = record.moves.count
            notice = past ? "\(engineName) declines the draw." : "\(engineName) declines the draw this early."
            Feel.shared.refuse()
            let shown = notice
            Task { try? await Task.sleep(for: .seconds(4)); if notice == shown { notice = nil } }
        }
    }

    /// A move suggested by the strongest setting of this engine (or Stockfish Lite, for an engine that doesn't
    /// search), shown as a soft arrow. Counted in the log.
    func askHint() {
        guard canHint else { return }
        hinting = true
        selected = nil
        let moves = record.moves, start = record.startFEN
        let helper = engine.id == "maia" ? (Shelf.shared.engine(Shelf.bundledID) ?? engine) : engine
        Task {
            defer { hinting = false }
            do {
                guard var s = try await Core.shared.call("settings", ["manifest": helper.coreArgs["manifest"]!, "level": 10, "seed": record.seed]) as? [String: Any]
                else { return }
                s["nodes"] = 300_000
                let v = try await Core.shared.call("think", ["engine": helper.coreArgs, "fen": start, "moves": moves, "settings": s, "level": 10, "seed": record.seed])
                guard record.moves == moves, myTurn, let m = (v as? [String: Any])?["move"] as? String,
                      let f = Square.index(m.prefix(2)), let t = Square.index(m.dropFirst(2).prefix(2)) else { return }
                hint = (f, t)
                record.hints = (record.hints ?? 0) + 1
                GameLog.shared.save(record)
                Feel.shared.select()
            } catch {
                notice = "No hint this time. Try again."
            }
        }
    }

    /// The game as PGN, and the position on the board as FEN, for copying and sharing.
    var pgn: String { GameLog.pgn(record) }
    var shownFEN: String {
        if let p = viewPly, positions.indices.contains(p), !positions[p].isEmpty { return positions[p] }
        return snap.fen
    }

    /// The premove, if it is legal now; otherwise it is dropped quietly.
    private func playPremove() async {
        guard let p = premove else { return }
        premove = nil
        guard myTurn, let m = Premove.resolve(from: p.from, to: p.to, legal: snap.legal) else { return }
        await play(m.uci, byEngine: false)
    }

    /// Leaving the screen: any search ends, the clocks stop; the game stays saved and the engine thinks again on return.
    func leave() {
        pauseClock()
        clockTask?.cancel()
        request += 1
        if thinking { thinking = false; Task { _ = try? await Core.shared.call("stop") } }
    }

    /// After an engine problem: ask again.
    func retry() {
        trouble = nil
        if snap.legal.isEmpty, !over { Task { await resume() } } else { engineIfDue() }
    }

    // MARK: Undo, resign, the end

    func undo() {
        guard canUndo else { return }
        drawOffered = false
        request += 1
        if thinking { thinking = false; Task { _ = try? await Core.shared.call("stop") } }
        var moves = record.moves
        moves.removeLast()
        // Back to your turn: take the engine's answer and your move.
        if moves.count % 2 != (record.player == "w" ? 0 : 1) { moves.removeLast() }
        record.undos += 1
        selected = nil
        viewPly = nil
        Feel.shared.select()
        Task {
            do {
                let s = try await Core.shared.decode(Snapshot.self, "state", ["fen": record.startFEN, "moves": moves])
                snap = s
                resetIDs()
                record.moves = s.moves; record.san = s.san; record.fen = s.fen
                GameLog.shared.save(record)
                await refreshPositions()
                engineIfDue()
            } catch { trouble = "Undo didn't work. Try again." }
        }
    }

    func resign() {
        guard !over else { return }
        request += 1
        if thinking { thinking = false; Task { _ = try? await Core.shared.call("stop") } }
        premove = nil
        let winner = record.player == "w" ? "b" : "w"
        finish(Snapshot.Outcome(result: winner == "w" ? "1-0" : "0-1", reason: "resigned", winner: winner))
    }

    /// The level the next adaptive game against this engine starts at, once one has been played.
    static func adaptiveLevel(_ engineID: String) -> Int? {
        UserDefaults.standard.object(forKey: "level.\(engineID)") as? Int
    }

    /// Where onboarding said to start every engine ("How well do you play?").
    static let startKey = "level.start"

    /// Where an adaptive game against this engine starts: its own record, else your answer at the start, else core's first level.
    static func startingLevel(_ engineID: String) async -> Int {
        if let l = adaptiveLevel(engineID) { return l }
        if let l = UserDefaults.standard.object(forKey: startKey) as? Int { return l }
        if let v = try? await Core.shared.call("levels") as? [String: Any], let f = v["first"] as? Int { return f }
        return 1
    }

    /// How long after a game ends its end card is up (GameScreen waits, then fades it in).
    static let endCardIn: Duration = .seconds(1.3)

    private func finish(_ o: Snapshot.Outcome) {
        drawOffered = false
        selected = nil
        premove = nil
        hint = nil
        clockTask?.cancel()
        if var c = clock { c.stop(at: Self.now()); clock = c; saveClock() }
        record.result = o.result
        record.ending = o.reason
        record.endedAt = Date()
        GameLog.shared.save(record)
        let outcome = record.outcome ?? "draw"
        if outcome == "win" { Feel.shared.won() } else { Feel.shared.ended() }
        // A game counts only for its own account: one finished on a board left open after another signed in doesn't.
        // That board still shows the old owner's game until it is left; it is not closed on an account switch.
        if GameLog.shared.countsHere(record) {
            EngineGames.finished(record)
            GameCenter.shared.gameEnded(record, strongest: record.level >= 10 || (record.rating != nil && record.rating == engine.manifest.ratings?.upperBound))
            Measure.gameEnded(engine: record.engineID, outcome: outcome, ending: o.reason, plies: record.moves.count, level: record.level,
                              clock: record.timeControl?.name)
        }
        // A rating may be asked for after a win, once the result has been on the screen a moment (ReviewRequest decides).
        // A resigned game is not one played to its end. A win from a chosen position is not a moment to ask at, and
        // a win with hints is never named a first win at its level.
        if rated { settleRated(resign: o.reason == "resigned") }
        if o.reason != "resigned" { ReviewRequest.shared.record(.finishedGame) }
        if outcome == "win", !record.fromPosition {
            let before = GameLog.shared.finished.contains {
                $0.id != record.id && $0.outcome == "win" && $0.engineID == record.engineID && $0.level == record.level && $0.rating == record.rating
            }
            ReviewRequest.shared.considerAsking(after: before || (record.hints ?? 0) > 0 ? .engineWin : .firstWinAtLevel, shownIn: Self.endCardIn)
        }
        // A game from a chosen position never counts toward adaptive play; a win with hints doesn't move it up.
        let helped = (record.hints ?? 0) > 0 && outcome == "win"
        if record.adaptive, !record.fromPosition, !helped {
            let level = record.level, id = record.engineID
            Task {
                var args: [String: Any] = ["level": level, "result": outcome]
                if let step = UserDefaults.standard.object(forKey: "step.\(id)") as? Int { args["step"] = step }
                if let r = try? await Core.shared.call("adapt", args) as? [String: Any], let next = (r["level"] as? NSNumber)?.intValue {
                    UserDefaults.standard.set(next, forKey: "level.\(id)")
                    if let step = (r["step"] as? NSNumber)?.intValue { UserDefaults.standard.set(step, forKey: "step.\(id)") }
                    nextLevel = next
                }
            }
        }
    }

    /// After an adaptive game: the level of the next one.
    private(set) var nextLevel: Int?

    /// Sending a rated game's result to Zeist is under way.
    private(set) var ratedSending = false

    /// Sends a finished rated game to Zeist, then reads the rating it left. Kept with the game, so the end card and
    /// Recent can say what came of it.
    private func settleRated(resign: Bool) {
        guard let id = record.ratedID, let by = record.ratedBy else { return }
        ratedSending = true
        let moves = record.moves
        Task {
            defer { ratedSending = false }
            let sent = await RatedFinishes.send(id, moves: moves, resign: resign, owner: by)
            if record.ratedID == id, record.ratedSent == nil { record.ratedSent = sent } // waiting: no answer yet
        }
    }

    /// Zeist answered for this game (RatedFinishes): what the log now holds for it.
    func settled(_ g: GameRecord) {
        guard g.id == record.id else { return }
        record.ratedSent = g.ratedSent
        record.ratingAfter = g.ratingAfter
        record.ratedGames = g.ratedGames
        record.nextRatedLevel = g.nextRatedLevel
    }

    /// Zeist's limit: a game that reaches 600 single moves is a draw, and no rated game is longer.
    static let moveLimit = 600

    #if DEBUG
    /// For screenshots and tests: a game with these moves already played.
    func load(_ moves: [String]) async {
        guard let s = try? await Core.shared.decode(Snapshot.self, "state", ["fen": record.startFEN, "moves": moves]) else { return }
        record.moves = s.moves; record.san = s.san; record.fen = s.fen
        snap = s
        resetIDs()
        if let c = clock {
            // A timed game part way: each side has spent a little on each move.
            let spent = (0..<moves.count).map { i in Double((i * 7) % 5 + 2) - (i < 2 ? 2 : 0) }
            var w = Double(c.control.base), b = w, clocks: [Int] = []
            for (i, t) in spent.enumerated() {
                if i % 2 == 0 { w += -t + (i > 0 ? Double(c.control.increment) : 0); clocks.append(Int(w * 1000)) }
                else { b += -t + Double(c.control.increment); clocks.append(Int(b * 1000)) }
            }
            record.clocks = clocks
            record.clockLeft = [Int(w * 1000), Int(b * 1000)]
            clock = ChessClock(control: c.control, white: w, black: b, running: moves.isEmpty ? nil : s.turn, paused: true)
        }
        GameLog.shared.save(record)
        await refreshPositions()
    }

    /// For screenshots: a premove already entered.
    func setPremove(_ uci: String) {
        guard let f = Square.index(uci.prefix(2)), let t = Square.index(uci.dropFirst(2).prefix(2)) else { return }
        premove = (f, t)
    }

    /// For screenshots and tests: set the time left on both clocks.
    func setClock(white: Double, black: Double) {
        guard let c = clock else { return }
        clock = ChessClock(control: c.control, white: white, black: black, running: c.running, paused: c.paused, at: Self.now())
        if !c.paused { resumeClockFresh() }
        saveClock()
    }

    private func resumeClockFresh() {
        guard var c = clock else { return }
        c.pause(at: Self.now()); c.resume(at: Self.now()); clock = c
        watchClock()
    }
    #endif

    // MARK: Words

    var engineName: String {
        #if DEBUG
        if let n = Debug.value("-engine-name") { return n }
        #endif
        return engine.name
    }

    var status: String {
        if let trouble { return trouble }
        if drawOffered, !over { return "\(engineName) offers a draw." }
        if let notice, !over { return notice }
        if over, viewPly == nil { return ending.detail }
        if let p = viewPly {
            guard p > 0, record.san.indices.contains(p - 1) else { return "The start. Tap the board to return." }
            return "\(Self.moveNumber(p, start: record.startFEN)) \(record.san[p - 1]). Tap the board to return."
        }
        if thinking { return premove != nil ? "\(engine.name) is thinking. Your next move is set." : "\(engine.name) is thinking." }
        if snap.check != nil { return "Check. Your move." }
        if record.moves.isEmpty && record.player == "w" { return "You play White. Your move." }
        return "Your move."
    }

    /// The status says only whose turn it is, which the rows beside the board already show.
    var statusIsPlain: Bool {
        trouble == nil && !drawOffered && (notice == nil || over) && !over && viewPly == nil && snap.check == nil && premove == nil
            && !(record.moves.isEmpty && record.player == "w")
    }

    var ending: (title: String, detail: String) {
        let why: String = switch record.ending {
        case "checkmate": "Checkmate."
        case "stalemate": "Stalemate."
        case "repetition": "The same position three times."
        case "fifty-move": "Fifty moves without a capture or a pawn move."
        case "insufficient": "Neither side can checkmate."
        case "resigned": "You resigned."
        case "agreement": "Draw agreed."
        case "engine-resigned": "\(engineName) resigned."
        case "move-limit": "Drawn at 300 moves, the longest a rated game can be."
        case "timeout": record.outcome == "win" ? "\(engine.name) ran out of time." : "Your time ran out."
        case "timeout-insufficient": record.outcome == "draw" && snap.turn == record.player
            ? "Your time ran out, but \(engine.name) had too little to checkmate."
            : "\(engine.name) ran out of time, but you had too little to checkmate."
        default: ""
        }
        switch record.outcome {
        case "win": return ("You won.", why)
        case "loss": return ("\(engine.name) won.", why)
        default: return ("A draw.", why)
        }
    }

    var levelLine: String {
        rated ? "Level \(record.level)" : record.difficulty
    }

    /// "12." for White's twelfth move, "12..." for Black's, after `ply` moves from the start position.
    static func moveNumber(_ ply: Int, start: String) -> String {
        let blackFirst = start.split(separator: " ").dropFirst().first == "b"
        let startNo = Int(start.split(separator: " ").last ?? "1") ?? 1
        let p = ply - 1 + (blackFirst ? 1 : 0)
        return "\(startNo + p / 2)\(p % 2 == 0 ? "." : "...")"
    }
}
