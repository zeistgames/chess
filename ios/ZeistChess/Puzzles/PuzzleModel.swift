import Foundation
import Observation
import UIKit

/// A puzzle being solved. The opponent's move is played first, then the solver answers; after each right move the
/// opponent replies, until the line ends. A wrong move goes back and may be tried again as often as wanted; after a
/// miss, Show the move plays out the rest of the line. A move that mates counts, whatever the line says (Lichess's rule).
/// No timer, no score, no streak. The rules come from core (the same rules as games), so no engine is involved.
@MainActor @Observable
final class PuzzleModel: BoardModel {
    enum Phase: Equatable {
        /// Reading the set, or setting up the position.
        case loading
        /// The position as given, a beat before the opponent's move.
        case intro
        /// The solver's turn.
        case solve
        /// The opponent is answering.
        case reply
        /// A wrong move on the board, about to go back.
        case wrong
        /// The line is played.
        case done
        /// Nothing to show: no puzzles could be read, or this one could not be set up.
        case empty
    }

    /// Where the puzzles come from: all of them by the step (the Puzzles place), one theme by the same step rule, or
    /// one day's daily puzzle. Each keeps its own puzzle in hand; solves count the same everywhere.
    enum Source: Equatable {
        case all
        case theme(PuzzleTheme)
        /// A day of the daily list and the list's start (the day a solve happens on is read at the solve).
        case daily(day: Int, puzzle: Puzzle, start: String)
    }

    /// The position as core gives it: board, legal moves, check, the end.
    typealias Rules = @MainActor (_ fen: String, _ moves: [String]) async throws -> Snapshot
    static let coreRules: Rules = { fen, moves in try await Core.shared.decode(Snapshot.self, "state", ["fen": fen, "moves": moves]) }

    private(set) var puzzle: Puzzle?
    private(set) var snap: Snapshot
    private(set) var ids: [Int?] = Array(repeating: nil, count: 64)
    var selected: Int?
    var promoting: (from: Int, to: Int)?
    var flipped = false
    private(set) var phase: Phase = .loading
    /// The moves of the line played so far, the opponent's first.
    private(set) var played: [String] = []
    /// A wrong move was made on this puzzle.
    private(set) var missed = false
    /// Show the move was used on this puzzle.
    private(set) var usedShow = false
    /// How the puzzle ended, once it has.
    private(set) var result: PuzzleProgress.Result?
    /// The quiet line under the board.
    private(set) var line = ""
    private(set) var progress: PuzzleProgress

    let source: Source
    /// Now, for the day a daily solve is recorded on: read at the moment of the solve, so one after local midnight
    /// counts for the new day. Injected in tests.
    var clock: @MainActor () -> Date = { DailyCalendar.now() }
    private let set: PuzzleSet
    private let defaults: UserDefaults
    private let rules: Rules
    /// Pauses are multiplied by this (0 in tests).
    var pace: Double
    /// The result is already counted (a puzzle tried again after it ended counts once).
    private var counted = false
    private var token = 0
    private var nextID = 0
    private var started = false

    /// A first finish counted where it counts beyond this device's progress. Replaceable in tests.
    var report: @MainActor (Puzzle, PuzzleProgress.Result) -> Void = { p, r in
        GameCenter.shared.puzzleDone(solved: r != .shown, firstTry: r == .solved, band: p.band)
        Measure.puzzleDone(band: p.band, result: r == .solved ? "solved" : r == .missed ? "solved_after_miss" : "shown")
    }

    init(set: PuzzleSet = .shared, source: Source = .all, defaults: UserDefaults = .standard, rules: @escaping Rules = PuzzleModel.coreRules, pace: Double = 1) {
        self.source = source
        self.set = set
        self.defaults = defaults
        self.rules = rules
        self.pace = pace
        progress = PuzzleProgress.load(defaults)
        snap = Self.still(GameModel.standardStart)
    }

    // MARK: What the screen reads

    /// "White to move." Said once, above the board.
    var turnLine: String { puzzle.map { $0.solver == "w" ? "White to move." : "Black to move." } ?? "" }
    /// "Mate in two." where the data says so.
    var goalLine: String {
        guard let m = puzzle?.mate, m > 0 else { return "" }
        let n = ["", "one", "two", "three", "four", "five"]
        return "Mate in \(m < n.count ? n[m] : String(m))."
    }
    var canShow: Bool { missed && phase == .solve }
    var canRetry: Bool { puzzle != nil && (played.count > 1 || phase == .done) && phase != .reply && phase != .wrong && phase != .intro }
    var canNext: Bool { phase != .loading && phase != .intro && !isDaily }
    var isDaily: Bool { if case .daily = source { true } else { false } }
    /// Daily: the day's puzzle is solved (on this device).
    var daySolved: Bool {
        guard case .daily(let day, _, _) = source else { return false }
        return progress.daily?[String(day)] != nil
    }

    /// Every screen's models write one saved progress: read it again before changing it, so none overwrites another's.
    private func fresh() { progress = PuzzleProgress.load(defaults) }

    /// The puzzle in hand for this source: the progress's `current` for all puzzles; for a theme, the device's own
    /// record kept apart (taking up or missing a theme puzzle leaves `current` alone); none for a day.
    private var inHand: PuzzleProgress.Current? {
        get {
            switch source {
            case .all: return progress.current
            case .theme(let t):
                guard let h = ThemeInHand.load(defaults), h.group == t.id else { return nil }
                return .init(id: h.id, band: h.band, missed: h.missed)
            case .daily: return nil
            }
        }
        set {
            switch source {
            case .all: progress.current = newValue
            case .theme(let t): ThemeInHand.save(newValue.map { ThemeInHand(group: t.id, id: $0.id, band: $0.band, missed: $0.missed) }, defaults)
            case .daily: break
            }
        }
    }

    /// The theme's next puzzle by the step rule (nothing is changed by looking).
    private func nextInTheme(_ t: PuzzleTheme) -> Puzzle? {
        let set = self.set
        return progress.next(inTheme: { set.puzzles(of: t, band: $0) })
    }
    /// The move the line expects now, for tests and the debug hook.
    var expected: String? { phase == .solve ? puzzle.flatMap { $0.moves.indices.contains(played.count) ? $0.moves[played.count] : nil } : nil }

    // MARK: BoardModel

    var player: String { puzzle?.solver ?? "w" }
    var whiteAtBottom: Bool { (player == "w") != flipped }
    var viewPly: Int? { nil }
    var shownBoard: [String] { snap.board }
    var shownLast: String? { snap.last }
    var premove: (from: Int, to: Int)? { nil }
    var hint: (from: Int, to: Int)? { nil }
    var canPremove: Bool { false }
    private var canMove: Bool { phase == .solve && snap.turn == player }

    private func legal(from i: Int) -> [Snapshot.Legal] {
        guard canMove else { return [] }
        let name = Square.name(i)
        return snap.legal.filter { $0.from == name }
    }

    func hints(from i: Int) -> [(to: Int, capture: Bool)] {
        let list = legal(from: i)
        return Set(list.map(\.to)).sorted().compactMap { name in
            Square.index(name).map { t in (t, !snap.board[t].isEmpty || list.contains { $0.to == name && $0.capture }) }
        }
    }

    private func isMine(_ i: Int) -> Bool { snap.board[i].hasPrefix(player) }
    func canLift(_ i: Int) -> Bool { isMine(i) && canMove }

    func tap(_ i: Int) {
        guard canMove else { selected = nil; return }
        if let s = selected {
            if s == i { selected = nil; return }
            if legal(from: s).contains(where: { $0.to == Square.name(i) }) { choose(from: s, to: i); return }
        }
        if isMine(i) {
            selected = i
            Feel.shared.select()
        } else {
            if selected != nil || !snap.board[i].isEmpty { Feel.shared.refuse() }
            selected = nil
        }
    }

    func drop(from: Int, to: Int) {
        guard from != to else { return }
        if legal(from: from).contains(where: { $0.to == Square.name(to) }) { choose(from: from, to: to) } else { Feel.shared.refuse() }
    }

    private func choose(from: Int, to: Int) {
        let options = legal(from: from).filter { $0.to == Square.name(to) }
        guard let first = options.first else { return }
        selected = nil
        if options.count > 1 {
            // "Always promote to a queen", unless the line wants another piece from this very move: then the choice is
            // offered, since a queen would be marked wrong for a reason the player never chose.
            let under = expected.map { $0.count == 5 && $0.prefix(4) == first.uci.prefix(4) && $0.last != "q" } ?? false
            if defaults.bool(forKey: GameModel.queenKey), !under, let q = options.first(where: { $0.promotion == "q" }) {
                Task { await attempt(q.uci) }
                return
            }
            promoting = (from, to)
            return
        }
        Task { await attempt(first.uci) }
    }

    func promote(_ piece: String) {
        guard let p = promoting else { return }
        promoting = nil
        Task { await attempt(Square.name(p.from) + Square.name(p.to) + piece) }
    }

    // MARK: The puzzle

    /// Opening Puzzles: the puzzle in hand comes back, else the next one.
    func start() async {
        guard !started else { return }
        started = true
        #if DEBUG
        if source == .all, let id = Debug.value("-puzzle"), let p = (1...PuzzleProgress.bands).lazy.compactMap({ self.set.find(id, band: $0) }).first {
            await begin(p); return
        }
        #endif
        fresh()
        switch source {
        case .daily(_, let p, _):
            await begin(p)
        case .theme(let t):
            if let c = inHand, progress.done[c.id] == nil, let p = set.find(c.id, band: c.band) { await begin(p, missed: c.missed) }
            else if let p = nextInTheme(t) { await begin(p) }
            else { allDone(t) }
        case .all:
            if let c = progress.current, progress.done[c.id] == nil, let p = set.find(c.id, band: c.band) {
                await begin(p, missed: c.missed)
            } else {
                await next()
            }
        }
    }

    /// Every puzzle of the theme solved or seen: said plainly.
    private func allDone(_ t: PuzzleTheme) {
        token += 1
        puzzle = nil
        phase = .empty
        line = "You have done every puzzle in \(t.name)."
    }

    private func empty() {
        token += 1
        puzzle = nil
        phase = .empty
        line = "No puzzles could be read."
    }

    /// The next puzzle. One left unfinished counts as seen; the difficulty stays where it was.
    func next() async {
        guard !isDaily else { return }
        fresh()
        if let p = puzzle, result == nil { progress.skip(p.id); inHand = nil }
        if case .theme(let t) = source {
            progress.save(defaults)
            if let p = nextInTheme(t) { await begin(p) } else { allDone(t) }
            return
        }
        let set = self.set
        let found = progress.next(in: { set.bandIfRead($0) })
        // Saved before the puzzle begins: begin reads the saved progress again.
        progress.save(defaults)
        guard let p = found else {
            token += 1
            puzzle = nil
            phase = .empty
            line = "No puzzles could be read."
            return
        }
        await begin(p)
    }

    /// Shown again (the Puzzles place coming back into view): if the puzzle in hand was solved meanwhile on another
    /// screen (a theme, the daily), go on to the next one rather than offer it to be counted twice.
    func moveOnIfDoneElsewhere() async {
        guard !isDaily, let p = puzzle, result == nil, phase == .solve || phase == .wrong || phase == .reply else { return }
        fresh()
        if progress.done[p.id] == 1 { await next() }
    }

    /// The same puzzle from its start. One already finished is not counted again.
    func retry() async {
        guard let p = puzzle, canRetry else { return }
        Feel.shared.select()
        // A day's puzzle seen through Show the move stays open: played again, it can still be solved for the day.
        if isDaily { usedShow = false }
        await begin(p, missed: missed, again: true)
    }

    func begin(_ p: Puzzle, missed: Bool = false, again: Bool = false) async {
        token += 1
        let t = token
        puzzle = p
        played = []
        self.missed = missed
        usedShow = again ? usedShow : false
        if !again { result = nil; counted = false; flipped = false }
        selected = nil
        promoting = nil
        line = ""
        phase = .loading
        snap = Self.still(p.fen)
        resetIDs()
        if case .daily(let day, _, _) = source, !again {
            fresh()
            self.missed = progress.dailyMissed?[String(day)] != nil
        }
        if !counted, !isDaily {
            fresh()
            inHand = .init(id: p.id, band: p.band, missed: missed)
            progress.save(defaults)
        }
        do {
            let s = try await rules(p.fen, [])
            guard t == token else { return }
            snap = s
            phase = .intro
            await pause(0.55)
            guard t == token else { return }
            try await advance(p.moves[0], opponent: true)
            guard t == token else { return }
            phase = .solve
        } catch {
            guard t == token else { return }
            phase = .empty
            line = "This puzzle couldn't be set up. Try the next one."
        }
    }

    /// The solver's move: right (the line's move, or any mate), or wrong (it goes back).
    func attempt(_ uci: String) async {
        guard phase == .solve, let p = puzzle, let expected else { return }
        let t = token
        let before = snap, beforeIDs = ids
        let capture = snap.legal.first { $0.uci == uci }?.capture ?? false
        // The piece moves at once; whether it was right is known a moment later.
        phase = .wrong
        optimistic(uci)
        do {
            let after = try await rules(p.fen, played + [uci])
            guard t == token else { return }
            let mate = after.outcome?.reason == "checkmate"
            if uci == expected || mate {
                phase = .reply
                commit(after, uci)
                Feel.shared.move(capture: capture)
                if after.check != nil, after.outcome == nil { Feel.shared.check() }
                if mate || played.count == p.moves.count { finish() } else { await reply() }
            } else {
                await wrong(before: before, ids: beforeIDs)
            }
        } catch {
            guard t == token else { return }
            snap = before
            ids = beforeIDs
            phase = .solve
            line = "That move couldn't be checked. Try again."
        }
    }

    /// The wrong move stays on the board for a moment, then the piece goes back.
    private func wrong(before: Snapshot, ids beforeIDs: [Int?]) async {
        let t = token
        Feel.shared.refuse()
        line = "Not that one."
        if !missed {
            missed = true
            markMissed()
        }
        await pause(0.52)
        guard t == token else { return }
        snap = before
        ids = beforeIDs
        phase = .solve
    }

    /// After a miss: the right move, played for the solver, and the line goes on.
    func showMove() async {
        guard canShow, let m = expected, let p = puzzle else { return }
        let t = token
        usedShow = true
        markMissed()
        selected = nil
        promoting = nil
        line = ""
        phase = .reply
        do {
            let capture = snap.legal.first { $0.uci == m }?.capture ?? false
            optimistic(m)
            let after = try await rules(p.fen, played + [m])
            guard t == token else { return }
            commit(after, m)
            Feel.shared.move(capture: capture)
            // The rest of the line plays itself out, as in Zeist: the whole solution is shown, then Next.
            var done = after.outcome != nil
            while !done, played.count < p.moves.count {
                await pause(0.55)
                guard t == token else { return }
                try await advance(p.moves[played.count], opponent: played.count % 2 == 0)
                guard t == token else { return }
                done = snap.outcome != nil
            }
            finish()
        } catch {
            guard t == token else { return }
            phase = .solve
            line = "That move couldn't be played. Try again."
        }
    }

    private func reply() async {
        guard let p = puzzle else { return }
        let t = token
        phase = .reply
        line = ""
        await pause(0.42)
        guard t == token else { return }
        do {
            try await advance(p.moves[played.count], opponent: true)
            guard t == token else { return }
            phase = .solve
            line = "Keep going."
        } catch {
            guard t == token else { return }
            phase = .empty
            line = "This puzzle couldn't be set up. Try the next one."
        }
    }

    /// A miss (or Show the move) on this puzzle, remembered with its puzzle in hand, and for a day's puzzle with the day.
    private func markMissed() {
        fresh()
        if case .daily(let day, _, _) = source {
            var m = progress.dailyMissed ?? [:]
            m[String(day)] = 1
            progress.dailyMissed = m
        } else if !counted {
            inHand?.missed = true
        }
        progress.save(defaults)
    }

    private func finish() {
        guard let p = puzzle else { return }
        let r: PuzzleProgress.Result = usedShow ? .shown : missed ? .missed : .solved
        result = r
        fresh()
        // A day's puzzle is recorded for its day only when it is solved (after a miss or a look at the move, missed: 1).
        if case .daily(let day, _, let start) = source, r != .shown {
            let on = DailyCalendar.day(at: clock(), start: start) ?? day
            progress.solveDaily(day: day, id: p.id, missed: missed, on: on)
            progress.save(defaults)
        }
        // The solver's moves as played: every other move after the opponent's first.
        let moves = played.enumerated().filter { $0.offset % 2 == 1 }.map(\.element).joined(separator: " ")
        // Solved after it was already counted as seen (a day's puzzle: Show the move, then Retry): it is solved now.
        if counted, r != .shown, progress.done[p.id] != 1 {
            progress.replayFinish(p.id, r, moves: moves, round: false)
            progress.save(defaults)
        }
        // One finish counts once, everywhere: a puzzle already solved or seen (before, or on another screen; a round
        // of playing the set again, a theme, a day's puzzle) moves no step and is counted nowhere again, and it is no
        // longer this screen's puzzle in hand. A solve of one only seen becomes a solve.
        if !counted, progress.done[p.id] != nil {
            counted = true
            var round = false
            if case .all = source { round = true }
            progress.replayFinish(p.id, r, moves: moves, round: round)
            if inHand?.id == p.id { inHand = nil }
            progress.save(defaults)
        }
        if !counted {
            progress.finish(p.id, r)
            inHand = nil
            progress.save(defaults)
            counted = true
            report(p, r)
        }
        phase = .done
        selected = nil
        line = r == .shown ? (isDaily ? "That was the line. Retry to solve it for this day." : "That was the line.") : "Solved."
        if r != .shown { Feel.shared.won() }
    }

    /// A move of the line played on the board (the opponent's, or the solver's after Show the move).
    private func advance(_ uci: String, opponent: Bool) async throws {
        guard let p = puzzle else { return }
        let capture = snap.legal.first { $0.uci == uci }?.capture ?? (Square.index(uci.dropFirst(2).prefix(2)).map { !snap.board[$0].isEmpty } ?? false)
        let t = token
        optimistic(uci)
        let after = try await rules(p.fen, played + [uci])
        guard t == token else { return } // the board has moved on (Next, Retry): this answer is for another
        commit(after, uci)
        if opponent { Feel.shared.reply(capture: capture) }
        if after.check != nil, after.outcome == nil, opponent { Feel.shared.check() }
    }

    private func commit(_ s: Snapshot, _ uci: String) {
        snap = s
        for i in 0..<64 {
            if s.board[i].isEmpty { ids[i] = nil } else if ids[i] == nil { nextID += 1; ids[i] = nextID }
        }
        played.append(uci)
    }

    private func pause(_ seconds: Double) async {
        let s = (UIAccessibility.isReduceMotionEnabled ? min(seconds, 0.12) : seconds) * pace
        if s > 0 { try? await Task.sleep(for: .seconds(s)) }
    }

    private func resetIDs() {
        ids = snap.board.map { $0.isEmpty ? nil : { nextID += 1; return nextID }() }
    }

    /// Moves the piece at once, carrying its identity so it glides; the rules confirm the board a moment later.
    private func optimistic(_ uci: String) {
        let c = Array(uci)
        guard c.count >= 4, let f = Square.index(String(c[0...1])), let t = Square.index(String(c[2...3])) else { return }
        var b = snap.board
        var ids = self.ids
        let piece = b[f]
        if piece.hasSuffix("P"), f % 8 != t % 8, b[t].isEmpty {
            let taken = t + (piece.hasPrefix("w") ? 8 : -8)
            if (0..<64).contains(taken) { b[taken] = ""; ids[taken] = nil }
        }
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

    /// A position to draw before the rules have answered.
    static func still(_ fen: String) -> Snapshot {
        Snapshot(fen: fen, turn: fen.split(separator: " ").dropFirst().first.map(String.init) ?? "w", board: Square.board(fromFEN: fen),
                 legal: [], check: nil, last: nil, moves: [], san: [], outcome: nil)
    }
}
