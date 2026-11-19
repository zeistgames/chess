import Foundation
import Observation
import UIKit

/// A lesson being played, step by step (docs/LESSONS.md). A show step is read, a move step wants one of its moves,
/// a pick step wants squares tapped. A wrong move goes back with a plain line; Hint gives the hint, then the move;
/// Next is never locked: on an unsolved step it shows the answer, and once the step is done it goes on. After the
/// right move (and its reply) or the last right tap, the lesson goes on by itself after a short pause, the after line
/// staying under the board until the player's next move or tap. Back steps to the step before, shown as it was left. The step in hand is kept, so leaving and coming back resumes there.
/// The rules come from core (the same rules as games and puzzles): no engine is involved.
@MainActor @Observable
final class LessonModel: BoardModel {
    enum Phase: Equatable {
        /// Setting up the step's position.
        case loading
        /// Moves are being played on the board: a show step's line, an answer, a reply.
        case busy
        /// The step waits for the player: a move or a square to tap (or, on a show step, Next).
        case ready
        /// A wrong move on the board, about to go back.
        case wrong
        /// The step is done; Next goes on.
        case solved
        /// The lesson is finished.
        case ended
        /// The step could not be set up.
        case broken
    }

    static let neutral = "Not the move this lesson is after."
    static let neutralSquare = "Not the square this lesson is after."

    let lesson: Lesson
    private(set) var index = 0
    private(set) var snap: Snapshot
    private(set) var ids: [Int?] = Array(repeating: nil, count: 64)
    var selected: Int?
    var promoting: (from: Int, to: Int)?
    private(set) var phase: Phase = .loading
    /// The quiet line under the board: whose move it is, a wrong move's line, the hint, the after line.
    private(set) var line = ""
    /// 0 before Hint; 1 after the first tap (the hint's words, and on a move step the piece to move lit); 2 once the
    /// move is shown with an arrow, or a pick step's answers are lit.
    private(set) var hintLevel = 0
    /// Pick steps: the right squares found so far (all of them once Next has shown them).
    private(set) var found: [String] = []
    /// Pick steps: the right squares shown by Hint.
    private(set) var hinted: [String] = []
    /// The step's marks stay as long as the step is open, through wrong tries too; they go when the lesson moves on.
    private(set) var marksShown = true
    /// The moves played on top of the step's position.
    private(set) var played: [String] = []
    /// The position each step opens on, as reached this time through (an accepted move other than the first, say).
    private var starts: [Int: String] = [:]
    /// The last move on the board when each step opens, so a step that continues keeps the tint of the reply before it.
    private var lasts: [Int: String] = [:]
    /// Each step as it was when done, so Back returns to it solved.
    private var solved: [Int: Solved] = [:]
    private struct Solved { let snap: Snapshot; let ids: [Int?]; let played: [String]; let found: [String]; let line: String; let start: String }
    /// The line under the board is the step before's after line, carried over until the player moves or taps.
    private(set) var carried = false
    private var start = ""

    private let store: LearnStore
    private let rules: PuzzleModel.Rules
    private let defaults: UserDefaults
    /// Pauses are multiplied by this (0 in tests).
    var pace: Double
    /// VoiceOver is running: the lesson then waits on a done step for Next, so the after line is read once and the
    /// next step's words are not cut off.
    var voiceOver: () -> Bool = { UIAccessibility.isVoiceOverRunning }
    private var token = 0
    private var nextID = 0
    private var started = false

    init(lesson: Lesson, store: LearnStore = .shared, defaults: UserDefaults = .standard, rules: @escaping PuzzleModel.Rules = PuzzleModel.coreRules, pace: Double = 1) {
        self.lesson = lesson
        self.store = store
        self.defaults = defaults
        self.rules = rules
        self.pace = pace
        snap = PuzzleModel.still(lesson.steps[0].fen ?? GameModel.standardStart)
        resetIDs()
    }

    // MARK: What the screen reads

    var step: LessonStep { lesson.steps[index] }
    var count: Int { lesson.steps.count }
    var isLast: Bool { index == count - 1 }
    var canBack: Bool { index > 0 && phase != .ended }
    var canHint: Bool { phase == .ready && step.kind != .show && hintLevel < 2 }
    var canNext: Bool { phase == .ready || phase == .solved }
    /// Next shows the answer rather than going on.
    var nextShows: Bool { phase == .ready && step.kind != .show }
    var turnLine: String { snap.turn == "w" ? "White to move." : "Black to move." }

    // MARK: BoardModel

    /// The side whose pieces move: whoever is to move in the step's position.
    var player: String { snap.turn }
    var whiteAtBottom: Bool { (step.side ?? lesson.side) == "w" }
    var viewPly: Int? { nil }
    var shownBoard: [String] { snap.board }
    var shownLast: String? { snap.last }
    var premove: (from: Int, to: Int)? { nil }
    var canPremove: Bool { false }
    var hint: (from: Int, to: Int)? {
        guard hintLevel >= 2, step.kind == .move, phase == .ready, let m = step.accept.first,
              let f = Square.index(m.prefix(2)), let t = Square.index(m.dropFirst(2).prefix(2)) else { return nil }
        return (f, t)
    }
    var marks: BoardMarks? {
        var m = BoardMarks(marksShown ? step.marks : nil, lit: found)
        for h in hinted { if let i = Square.index(h), !m.rings.contains(i) { m.rings.append(i) } }
        // The first tap of Hint lights the piece to move.
        if hintLevel == 1, step.kind == .move, phase == .ready, let f = step.accept.first.flatMap({ Square.index($0.prefix(2)) }) { m.lit.append(f) }
        return m
    }

    private var canMove: Bool { phase == .ready && step.kind == .move }

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
        // The step before's after line gives way to the player's own turn.
        if carried { carried = false; line = step.kind == .move ? turnLine : "" }
        if step.kind == .pick, phase == .ready { pick(Square.name(i)); return }
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
            // "Always promote to a queen", unless the lesson wants another piece from this very move.
            let under = step.accept.contains { $0.count == 5 && $0.prefix(4) == first.uci.prefix(4) && $0.last != "q" }
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

    // MARK: Steps

    /// Opening the lesson: the step in hand when it is this lesson's, else the first.
    func start(at asked: Int? = nil) async {
        guard !started else { return }
        started = true
        var n = 0
        if let c = store.progress.current, c.id == lesson.id { n = c.step }
        if let asked { n = asked }
        await open(min(max(0, n), count - 1))
    }

    /// Sets up step n: its position, the line of a show step, and the step's marks.
    func open(_ n: Int, carry: String? = nil) async {
        token += 1
        let t = token
        index = n
        phase = .loading
        line = ""
        carried = false
        hintLevel = 0
        found = []
        hinted = []
        marksShown = true
        selected = nil
        promoting = nil
        played = []
        store.at(lesson.id, step: n)
        do {
            let fen = try await startFEN(n)
            guard t == token else { return }
            start = fen
            let first = try await rules(fen, [])
            guard t == token else { return } // another step opened meanwhile
            snap = first
            // Continuing from the step before: its last move keeps its tint.
            if step.fen == nil { snap.last = lasts[n] }
            resetIDs()
            if step.kind == .show, !step.play.isEmpty {
                phase = .busy
                for m in step.play {
                    await pause(0.6)
                    guard t == token else { return }
                    try await advance(m, opponent: false)
                    guard t == token else { return }
                }
            }
            if step.kind == .move { line = turnLine }
            if let carry, step.kind != .show || line.isEmpty { line = carry; carried = true }
            if step.kind == .show { done() } else { phase = .ready }
        } catch {
            guard t == token else { return }
            phase = .broken
            line = "This step couldn't be set up."
        }
    }

    /// Next: on a step not yet done, the answer; on a done step, the step after (or the end).
    func next() async {
        switch phase {
        case .ready:
            switch step.kind {
            case .move: if let m = step.accept.first { await play(m, answer: true) }
            case .pick:
                found = step.accept
                hinted = []
                line = step.after ?? ""
                done()
                await goOn()
            case .show: done()
            }
        case .solved:
            Feel.shared.select()
            if isLast { end() } else { await open(index + 1) }
        default: break
        }
    }

    func back() async {
        guard canBack else { return }
        Feel.shared.select()
        let n = index - 1
        guard let s = solved[n] else { await open(n); return }
        token += 1
        index = n
        snap = s.snap; ids = s.ids; played = s.played; found = s.found; line = s.line; start = s.start
        carried = false
        hintLevel = 0
        hinted = []
        marksShown = true
        selected = nil
        promoting = nil
        phase = .solved
        store.at(lesson.id, step: n)
    }

    /// After a step done by the player (or by Next), the next step follows by itself, a beat after the last move lands.
    private func goOn() async {
        guard !voiceOver() else { return }
        let t = token, i = index
        await pause(1.0)
        guard t == token, index == i, phase == .solved else { return }
        if isLast { end() } else { await open(i + 1, carry: line.isEmpty ? nil : line) }
    }

    /// Hint, as in the approved design: the first tap gives the hint's words (where the step has them) and, on a
    /// move step, lights the piece to move; the second shows the move with an arrow, or lights a pick step's answers.
    /// A pick step without words goes straight to its answers.
    func useHint() {
        guard canHint else { return }
        Feel.shared.select()
        if hintLevel == 0, step.kind == .move || step.hint != nil {
            hintLevel = 1
            if let h = step.hint { line = h }
            return
        }
        hintLevel = 2
        if step.kind == .pick { hinted = step.accept.filter { !found.contains($0) } }
    }

    /// The player's move: one the step accepts, or a wrong one that goes back.
    func attempt(_ uci: String) async {
        guard canMove else { return }
        carried = false
        if step.accept.contains(uci) { await play(uci, answer: false); return }
        // A move in also is good but not the one this lesson follows: it goes back like a wrong one, with its line.
        let good = step.also[uci]
        let t = token
        let before = snap, beforeIDs = ids
        phase = .wrong
        selected = nil
        optimistic(uci)
        if good == nil { Feel.shared.refuse() } else { Feel.shared.select() }
        line = good ?? step.wrong[uci] ?? Self.neutral
        await pause(0.6)
        guard t == token else { return }
        snap = before
        ids = beforeIDs
        marksShown = true
        phase = .ready
    }

    /// A tapped square on a pick step.
    func pick(_ square: String) {
        guard phase == .ready, step.kind == .pick, !found.contains(square) else { return }
        guard step.accept.contains(square) else {
            Feel.shared.refuse()
            line = step.wrong[square] ?? Self.neutralSquare
            return
        }
        Feel.shared.select()
        found.append(square)
        hinted.removeAll { $0 == square }
        if !step.all || step.accept.allSatisfy(found.contains) {
            line = step.after ?? ""
            done()
            Task { await goOn() }
        } else {
            line = ""
        }
    }

    /// An accepted move, by the player or by Next: it stays, the after line shows, and the reply follows.
    private func play(_ uci: String, answer: Bool) async {
        let t = token
        let capture = snap.legal.first { $0.uci == uci }?.capture ?? false
        phase = .busy
        selected = nil
        promoting = nil
        do {
            try await advance(uci, opponent: false)
            guard t == token else { return }
            Feel.shared.move(capture: capture)
            if snap.outcome?.reason == "checkmate" { Feel.shared.won() } else if snap.check != nil { Feel.shared.check() }
            line = step.after ?? ""
            if let r = step.reply[uci], snap.outcome == nil {
                await pause(0.5)
                guard t == token else { return }
                try await advance(r, opponent: true)
                guard t == token else { return }
            }
            done()
            await goOn()
        } catch {
            guard t == token else { return }
            let back = try? await rules(start, [])
            guard t == token else { return }
            snap = back ?? snap
            played = []
            resetIDs()
            marksShown = true
            phase = .ready
            line = "That move couldn't be played. Try again."
            ReviewRequest.shared.record(.trouble)
        }
    }

    /// The step is done: the position it leaves is where the next step without a fen begins.
    private func done() {
        phase = .solved
        selected = nil
        carried = false
        setStart(index + 1, snap.fen, last: snap.last)
        solved[index] = Solved(snap: snap, ids: ids, played: played, found: found, line: line, start: start)
        for k in solved.keys where k > index { solved[k] = nil }
    }

    private func end() {
        let first = !store.isFinished(lesson.id)
        store.finish(lesson.id)
        // A rating may be asked for when this lesson finishes its chapter or its course for the first time.
        if first, let course = LessonLibrary.shared.course(lesson.course) {
            let done = { (entries: [LessonIndex.Entry]) in entries.allSatisfy { self.store.isFinished($0.id) } }
            if done(course.entries) { ReviewRequest.shared.considerAsking(after: .lessonCourse) }
            else if let chapter = course.chapters.first(where: { c in c.lessons.contains { $0.id == self.lesson.id } }), done(chapter.lessons) {
                ReviewRequest.shared.considerAsking(after: .lessonChapter)
            }
        }
        phase = .ended
        line = ""
    }

    private func setStart(_ n: Int, _ fen: String, last: String?) {
        guard n < count else { return }
        starts[n] = fen
        lasts[n] = last
        // Later steps were reached through the old position; they are worked out again when needed.
        for k in starts.keys where k > n { starts[k] = nil; lasts[k] = nil }
    }

    /// The position step n opens on: its own fen, or where the step before left off. Never reached this time
    /// (resuming, or -lesson-step), the step before is played through by its first accepted move.
    func startFEN(_ n: Int) async throws -> String {
        if let f = lesson.steps[n].fen { return f }
        if let s = starts[n] { return s }
        guard n > 0 else { throw LessonData.Fault("the first step has no position") }
        let before = try await startFEN(n - 1)
        let line = Self.line(of: lesson.steps[n - 1])
        let fen = line.isEmpty ? before : try await rules(before, line).fen
        starts[n] = fen
        lasts[n] = line.last ?? (lesson.steps[n - 1].fen == nil ? lasts[n - 1] : nil)
        return fen
    }

    /// The moves a step leaves on the board when played by its first accepted move.
    static func line(of s: LessonStep) -> [String] {
        switch s.kind {
        case .show: return s.play
        case .pick: return []
        case .move:
            guard let m = s.accept.first else { return [] }
            return [m] + (s.reply[m].map { [$0] } ?? [])
        }
    }

    // MARK: The board

    private func advance(_ uci: String, opponent: Bool) async throws {
        let capture = snap.legal.first { $0.uci == uci }?.capture ?? (Square.index(uci.dropFirst(2).prefix(2)).map { !snap.board[$0].isEmpty } ?? false)
        let t = token
        optimistic(uci)
        let after = try await rules(start, played + [uci])
        guard t == token else { return } // the lesson has moved on (Back, Next): this answer is for another step
        commit(after, uci)
        if opponent {
            Feel.shared.reply(capture: capture)
            if after.check != nil, after.outcome == nil { Feel.shared.check() }
        }
    }

    private func commit(_ s: Snapshot, _ uci: String) {
        snap = s
        for i in 0..<64 {
            if s.board[i].isEmpty { ids[i] = nil } else if ids[i] == nil { nextID += 1; ids[i] = nextID }
        }
        played.append(uci)
    }

    /// Reduce Motion calms the board's movement (BoardView), never the time to read: pauses keep their length.
    static func delay(_ seconds: Double, pace: Double) -> Double { seconds * pace }

    private func pause(_ seconds: Double) async {
        let s = Self.delay(seconds, pace: pace)
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
}
