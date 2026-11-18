import Foundation

/// Where the player is with puzzles, kept on this device: the step of difficulty, which puzzles have been seen,
/// and the one in hand. The same rules as Zeist's puzzles (public/s/chess/puzzle.js there): unrated, sixteen quiet
/// steps, two to each band; up one after a solve with no miss, down one after a solve that took more than one try,
/// down two after Show the move. Nothing about it is shown.
struct PuzzleProgress: Codable, Equatable {
    enum Result: String, Codable { case solved, missed, shown }

    static let bands = 8
    static let steps = bands * 2

    var step = 0
    /// Puzzle id to 1 (solved) or 0 (seen, not solved).
    var done: [String: Int] = [:]
    /// The puzzle in hand, so it comes back when Puzzles is opened again.
    var current: Current?
    /// The daily puzzle, by day number: written when a day's puzzle is solved.
    var daily: [String: DailyRecord]?
    /// Days whose puzzle took a miss or Show the move, so a later solve of that day records missed: 1.
    var dailyMissed: [String: Int]?
    /// Not yet sent to the account (sending comes later; the shape is Zeist's PUZZLE-PROGRESS.md).
    var out: Out?

    struct Out: Codable, Equatable {
        var daily: [String: DailyRecord] = [:]
        var solved: [String: String]?
        var seen: [String: Int]?
    }

    struct Current: Codable, Equatable {
        var id: String
        var band: Int
        var missed = false
    }

    static func clamp(_ s: Int) -> Int { min(steps - 1, max(0, s)) }
    static func bandOf(step: Int) -> Int { min(bands, max(1, clamp(step) / 2 + 1)) }
    var band: Int { Self.bandOf(step: step) }

    static func nextStep(_ step: Int, _ result: Result) -> Int {
        switch result {
        case .solved: clamp(step + 1)
        case .missed: clamp(step - 1)
        case .shown: clamp(step - 2)
        }
    }

    /// Bands to look in, nearest first, the harder one first on a tie: 3 gives 3, 4, 2, 5, 1, 6, 7, 8.
    static func bandOrder(_ band: Int) -> [Int] {
        var out = [band]
        for d in 1..<bands {
            if band + d <= bands { out.append(band + d) }
            if band - d >= 1 { out.append(band - d) }
        }
        return out
    }

    /// A puzzle finished: it is marked, and the step moves. A puzzle solved before stays solved.
    mutating func finish(_ id: String, _ result: Result) {
        done[id] = result == .shown ? (done[id] ?? 0) : 1
        step = Self.nextStep(step, result)
        if current?.id == id { current = nil }
    }

    /// A day's puzzle solved: recorded once, the earlier and cleaner solve kept, and queued to send.
    mutating func solveDaily(day: Int, id: String, missed: Bool, on: Int) {
        let key = String(day)
        let r = DailyRecord(id: id, missed: missed || dailyMissed?[key] != nil ? 1 : 0, on: on)
        var d = daily ?? [:]
        d[key] = d[key].map { DailyRecord.merge($0, r) } ?? r
        daily = d
        var o = out ?? Out()
        o.daily[key] = o.daily[key].map { DailyRecord.merge($0, r) } ?? d[key]
        out = o
    }

    /// The days solved, as day number to the day it was solved on, for the count.
    var dailySolvedOn: [Int: Int] {
        (daily ?? [:]).reduce(into: [:]) { out, e in if let d = Int(e.key) { out[d] = e.value.on } }
    }

    /// The first puzzle of a theme by the same rule as next(in:): the step's band first, then the nearest, the first
    /// the player has neither solved nor seen. Seen puzzles are not offered again in a theme: nil when it is all done.
    /// Nothing here changes.
    func next(inTheme band: (Int) -> [Puzzle]) -> Puzzle? {
        for b in Self.bandOrder(self.band) { if let p = band(b).first(where: { done[$0.id] == nil }) { return p } }
        return nil
    }

    /// A puzzle left before it was finished (Next): seen, and the step stays.
    mutating func skip(_ id: String) {
        if done[id] == nil { done[id] = 0 }
        if current?.id == id { current = nil }
    }

    /// The puzzles finished in the current round of playing the set again, as id to 1: this device's own. It is never
    /// sent and no answer from Zeist changes it; an id in it that isn't in `done` means nothing. When owners are kept
    /// apart and someone signs in after playing signed out (PUZZLE-PROGRESS.md, "Signing in on a device that has
    /// played signed out"): if the account has nothing on this device yet, the guest's copy, `again` included, becomes
    /// the account's; otherwise the account keeps its own step and its own `again`, and the guest's `again` goes.
    var again: [String: Int]?
    /// What an earlier build of this app called `again` (a set of ids). Read once by load(), then gone.
    private var replayed: Set<String>?

    // The logical clock of `step` and `current` (PUZZLE-PROGRESS.md, `clock`) is not kept by this app yet. Where the
    // doc says "clock goes up by 1" (taking up a puzzle, its first miss, finishing it, and in replayFinish below), the
    // sync client adds `var clock: Int` and does it in touch().
    private mutating func touch() {}

    /// The next puzzle (Zeist's nextInSet). The first neither solved nor seen, by the step's band and then the nearest.
    /// band(n) gives a band's puzzles, or nil when a file of it can't be read now: such a band is not known, never used
    /// up, and if nothing unfinished is found while one was missing, nothing is offered and nothing changes. Only when
    /// every file was read and every puzzle is in `done` does the set play again, in rounds marked in `again`: seen and
    /// not solved first, then any not in `again`; when every puzzle is in `again`, it empties and a round begins.
    /// Taking a puzzle up marks nothing (replayFinish does, when it is finished). `done` is never cleared.
    mutating func next(in band: (Int) -> [Puzzle]?) -> Puzzle? {
        var short = false
        func scan(_ skip: (String) -> Bool) -> Puzzle? {
            for b in Self.bandOrder(self.band) {
                guard let list = band(b) else { short = true; continue }
                if let p = list.first(where: { !skip($0.id) }) { return p }
            }
            return nil
        }
        let fresh = scan { done[$0] != nil }
        if fresh != nil || short { return fresh }
        let a = again ?? [:]
        if let p = scan({ done[$0] == 1 || a[$0] != nil }) ?? scan({ a[$0] != nil }) { return p }
        if a.isEmpty { return nil }
        again = [:]
        return scan { done[$0] == 1 } ?? scan { _ in false }
    }

    /// A puzzle finished while it was already in `done` (Zeist's replayFinish): it counts once. The step stays; a solve
    /// of one only seen makes it solved and queues the solve (moves: the solver's moves as played); a solve of one
    /// already solved, and Show the move, change nothing in `done` or `out`. round: finished in a round of playing the
    /// set again (the run of all puzzles), so its id goes into `again`. If it was `current`, `current` becomes null.
    /// Answers whether `done` changed.
    @discardableResult
    mutating func replayFinish(_ id: String, _ r: Result, moves: String, round: Bool = true) -> Bool {
        if round { again = (again ?? [:]).merging([id: 1]) { a, _ in a } }
        if current?.id == id { current = nil; touch() }
        guard r != .shown, done[id] != 1 else { return false }
        done[id] = 1
        var o = out ?? Out()
        o.solved = (o.solved ?? [:]).merging([id: moves]) { _, b in b }
        o.seen?[id] = nil
        out = o
        return true
    }

    // MARK: Kept on this device

    static let key = "puzzles.progress"

    static func load(_ defaults: UserDefaults = .standard) -> PuzzleProgress {
        guard let d = defaults.data(forKey: key), let p = try? JSONDecoder().decode(PuzzleProgress.self, from: d) else { return PuzzleProgress() }
        var out = p
        out.step = clamp(p.step)
        if let r = p.replayed {
            var a = out.again ?? [:]
            for id in r { a[id] = 1 }
            out.again = a
            out.replayed = nil
        }
        return out
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let d = try? JSONEncoder().encode(self) { defaults.set(d, forKey: Self.key) }
    }
}

/// The theme puzzle in hand: the device's own, kept apart from the progress and never sent, with its miss, so the
/// same puzzle comes back (Zeist's PUZZLE-PROGRESS.md, "Themes"; the web keeps the same under chess-puzzles-theme).
/// One at a time: opening another theme takes up that theme's next puzzle.
struct ThemeInHand: Codable, Equatable {
    var group: String
    var id: String
    var band: Int
    var missed = false

    /// Kept per owner (the signed-in account's owner tag, or the guest), so it is ready to stay apart when progress syncs.
    @MainActor static var key: String { "puzzles.theme." + (Account.shared.owner ?? "guest") }

    @MainActor static func load(_ defaults: UserDefaults = .standard) -> ThemeInHand? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(ThemeInHand.self, from: $0) }
    }

    @MainActor static func save(_ t: ThemeInHand?, _ defaults: UserDefaults = .standard) {
        if let t, let d = try? JSONEncoder().encode(t) { defaults.set(d, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}
