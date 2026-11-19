import Foundation

/// Where the player is with puzzles: the step of difficulty, which puzzles have been solved or seen, the one in
/// hand, and the daily puzzle's days. The same rules as Zeist's puzzles (public/s/chess/puzzle.js there): unrated,
/// sixteen quiet steps, two to each band; up one after a solve with no miss, down one after a solve that took more
/// than one try, down two after Show the move.
/// This is the device's working copy, one for each owner (each Zeist account that has signed in here, and the
/// guest). Signed in, it is shared with Zeist through the account (PuzzleSync; Zeist's docs/PUZZLE-PROGRESS.md is
/// the contract): `out` is what the account has not yet taken.
struct PuzzleProgress: Codable, Equatable {
    enum Result: String, Codable { case solved, missed, shown }

    static let bands = 8
    static let steps = bands * 2

    var step = 0
    /// Puzzle id to 1 (solved) or 0 (seen, not solved).
    var done: [String: Int] = [:]
    /// The puzzle in hand, so it comes back when Puzzles is opened again.
    var current: Current?
    /// The daily puzzle, by day number: written at the first finish of a day's puzzle, and then the day's for good.
    var daily: [String: DailyRecord]?
    /// Days whose puzzle took a miss before it was finished, so the finish records missed: 1.
    var dailyMissed: [String: Int]?
    /// Not yet taken by the account: solves with the solver's moves as played (the proof), puzzles seen, daily rows.
    var out: Out?
    /// The logical clock of `step` and `current`: up by one on every change of either. The account keeps the copy
    /// with the higher clock, so no device's wall clock is trusted.
    var clock: Int?
    /// The cursor from the account's last answer.
    var since: Int?
    /// Puzzles solved here whose moves were never kept (a build before solves carried their proof): solved on this
    /// device, only seen on the account. Solving one again queues the solve with its moves; the account's "solved"
    /// takes it off this list.
    var unproven: [String: Int]?

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

    /// A puzzle finished: it is marked, queued for the account (a solve with its moves, the proof; Show the move as
    /// seen), and the step moves. A puzzle solved before stays solved.
    /// moves: the solver's moves as played, separated by spaces.
    mutating func finish(_ id: String, _ result: Result, moves: String = "") {
        done[id] = result == .shown ? (done[id] ?? 0) : 1
        var o = out ?? Out()
        if result == .shown {
            if o.solved?[id] == nil { o.seen = (o.seen ?? [:]).merging([id: 1]) { a, _ in a } }
        } else {
            o.solved = (o.solved ?? [:]).merging([id: moves]) { _, b in b }
            o.seen?[id] = nil
        }
        out = o
        step = Self.nextStep(step, result)
        if current?.id == id { current = nil }
        touch()
    }

    /// The first finish of a day's puzzle: solved with or without a miss, or Show the move, which counts as a miss.
    /// Recorded once and queued to send. Once a day has its record it is the day's for good: playing it again
    /// records nothing, so a later clean solve never takes a missed day's place.
    mutating func solveDaily(day: Int, id: String, missed: Bool, on: Int) {
        let key = String(day)
        guard daily?[key] == nil else { return }
        let r = DailyRecord(id: id, missed: missed || dailyMissed?[key] != nil ? 1 : 0, on: on)
        daily = (daily ?? [:]).merging([key: r]) { a, _ in a }
        var o = out ?? Out()
        o.daily[key] = o.daily[key].map { DailyRecord.merge($0, r) } ?? r
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

    /// A puzzle left before it was finished (Next): seen on this device, and the step stays.
    mutating func skip(_ id: String) {
        // Not queued for the account: leaving a puzzle is not seeing its answer (the main Zeist app sends none either).
        if done[id] == nil { done[id] = 0 }
        if current?.id == id { current = nil; touch() }
    }

    /// The puzzle in hand changed (one taken up, or its first miss): the clock goes up.
    mutating func take(_ c: Current?) {
        guard current != c else { return }
        current = c
        touch()
    }

    /// The puzzles finished in the current round of playing the set again, as id to 1: this device's own. It is never
    /// sent and no answer from Zeist changes it; an id in it that isn't in `done` means nothing. When owners are kept
    /// apart and someone signs in after playing signed out (PUZZLE-PROGRESS.md, "Signing in on a device that has
    /// played signed out"): if the account has nothing on this device yet, the guest's copy, `again` included, becomes
    /// the account's; otherwise the account keeps its own step and its own `again`, and the guest's `again` goes.
    var again: [String: Int]?
    /// What an earlier build of this app called `again` (a set of ids). Read once by load(), then gone.
    private var replayed: Set<String>?

    private mutating func touch() { clock = (clock ?? 0) + 1 }

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
        // One solved here by an earlier build, with no moves kept, is only seen on the account: this solve is its proof.
        guard r != .shown, done[id] != 1 || unproven?[id] != nil else { return false }
        let changed = done[id] != 1
        done[id] = 1
        var o = out ?? Out()
        o.solved = (o.solved ?? [:]).merging([id: moves]) { _, b in b }
        o.seen?[id] = nil
        out = o
        return changed
    }

    // MARK: Shared through the account (Zeist's docs/PUZZLE-PROGRESS.md)

    /// What one request carries of `out`: at most `max` items, solves first. skip: ids (and "day:<n>" for daily rows)
    /// the account put off in this sync, left out so the items after them still go.
    struct Outgoing: Equatable {
        var solved: [(id: String, moves: [String])] = []
        var seen: [String] = []
        var daily: [(day: Int, row: DailyRecord)] = []
        var isEmpty: Bool { solved.isEmpty && seen.isEmpty && daily.isEmpty }
        static func == (a: Outgoing, b: Outgoing) -> Bool {
            a.solved.map(\.id) == b.solved.map(\.id) && a.solved.map(\.moves) == b.solved.map(\.moves) && a.seen == b.seen
                && a.daily.map(\.day) == b.daily.map(\.day) && a.daily.map(\.row) == b.daily.map(\.row)
        }
    }

    func outgoing(max: Int = 100, skip: Set<String> = []) -> Outgoing {
        var o = Outgoing()
        // In a fixed order, so a queue longer than one request goes out the same way each time.
        for (id, m) in (out?.solved ?? [:]).sorted(by: { $0.key < $1.key }) where !skip.contains(id) && o.solved.count < max {
            o.solved.append((id, m.split(separator: " ").map(String.init)))
        }
        for id in (out?.seen ?? [:]).keys.sorted() where !skip.contains(id) && o.solved.count + o.seen.count < max { o.seen.append(id) }
        for (d, r) in (out?.daily ?? [:]).sorted(by: { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }) {
            guard let day = Int(d), !skip.contains("day:\(d)"), o.solved.count + o.seen.count + o.daily.count < max else { continue }
            o.daily.append((day, r))
        }
        return o
    }

    /// The account's answers to what was sent, settled against that request (`sent`), so nothing queued while it was
    /// out is lost: a solve leaves `out` only if it went with the moves still queued, a seen puzzle only if it went.
    /// A solve the account counted is proven; one it refused ("wrong") stays solved here and is queued as seen, so
    /// the account has the puzzle finished and a day's row for it can settle (as a miss). One put off ("later") stays.
    /// A daily row the account kept leaves `out` and the account's row for the day takes this device's place; one
    /// whose puzzle is not finished on the account yet ("unsolved") stays; one refused ("wrong") leaves, and with it
    /// this device's own row for that day, so a day played on a clock set ahead is not shown as done.
    mutating func settle(_ a: PuzzleAnswer, sent: Outgoing) {
        let solves = Dictionary(sent.solved.map { ($0.id, $0.moves.joined(separator: " ")) }) { a, _ in a }
        let seens = Set(sent.seen), days = Set(sent.daily.map(\.day))
        for r in a.results where r.status != "later" {
            if let m = solves[r.id] {
                if out?.solved?[r.id] == m { out?.solved?[r.id] = nil }
                if r.status == "solved" { unproven?[r.id] = nil }
                if r.status == "wrong", out?.solved?[r.id] == nil {
                    var o = out ?? Out()
                    o.seen = (o.seen ?? [:]).merging([r.id: 1]) { a, _ in a }
                    out = o
                }
            } else if seens.contains(r.id) {
                out?.seen?[r.id] = nil
            }
        }
        for r in a.dailyResults where r.status != "unsolved" && days.contains(r.day) {
            let key = String(r.day)
            if r.status == "wrong", let q = out?.daily[key], let mine = daily?[key], mine.id == q.id, mine.on == q.on { daily?[key] = nil }
            out?.daily[key] = nil
            if r.status == "kept", let row = r.row { daily = (daily ?? [:]).merging([key: row]) { _, b in b } }
        }
    }

    /// The account's progress folded in. Solved is a union and wins over seen; the account's daily rows take this
    /// device's; the cursor moves on. Step and the puzzle in hand become the account's only if nothing changed here
    /// while the request was out (`sent` is the clock it carried): otherwise the device's stay, and the next sync
    /// settles it.
    mutating func merge(_ a: PuzzleAnswer, sent: Int) {
        for id in a.solved { done[id] = 1 }
        for (d, r) in a.daily { daily = (daily ?? [:]).merging([d: r]) { _, b in b } }
        for id in a.seen where done[id] != 1 { done[id] = 0 }
        if let c = a.cursor { since = c }
        guard (clock ?? 0) == sent, let theirs = a.clock, let st = a.step else { return }
        step = Self.clamp(st)
        // One already finished here is not taken up again.
        current = a.current.flatMap { c in done[c.id] == nil ? Current(id: c.id, band: c.band ?? current?.band ?? 1, missed: c.missed) : nil }
        clock = theirs
    }

    /// Someone signs in on a device that has played signed out: the guest's progress joins the account's copy here.
    /// `done` is a union with solved winning, and `out` a union. A guest's day joins only where the account has no
    /// row for it here or its own row is still unsent. The account keeps its own step, clock and `again`.
    mutating func fold(guest g: PuzzleProgress) {
        for (id, v) in g.done where v == 1 || done[id] == nil { done[id] = v == 1 ? 1 : 0 }
        var o = out ?? Out()
        o.solved = (o.solved ?? [:]).merging(g.out?.solved ?? [:]) { _, b in b }
        o.seen = (o.seen ?? [:]).merging(g.out?.seen ?? [:]) { a, _ in a }
        for id in (o.solved ?? [:]).keys { o.seen?[id] = nil }   // a queued solve is never also sent as seen
        for (id, v) in g.unproven ?? [:] where o.solved?[id] == nil { unproven = (unproven ?? [:]).merging([id: v]) { a, _ in a } }
        for (d, row) in g.daily ?? [:] {
            // A day the account already has from Zeist is the day's for good: the guest's row can't take its place.
            if daily?[d] != nil, o.daily[d] == nil { continue }
            guard (daily?[d].map { DailyRecord.merge($0, row) } ?? row) == row else { continue }
            daily = (daily ?? [:]).merging([d: row]) { _, b in b }
            // Queued only if the guest had it queued; the account's own queued row for the day is left as it is.
            if g.out?.daily[d] != nil { o.daily[d] = row }
        }
        for (d, v) in g.dailyMissed ?? [:] { dailyMissed = (dailyMissed ?? [:]).merging([d: v]) { a, _ in a } }
        out = o
    }

    /// A copy that never had an answer from the account (a guest's; or one from a build that kept one progress for
    /// the whole device, sent nothing and kept no moves). The account counts a solve only with its moves, so a puzzle
    /// solved here with no moves kept stays solved on this device, goes to the account as seen, and is remembered as
    /// unproven: solving it again sends the solve with its proof. A daily row goes only with its puzzle finished
    /// (a day whose puzzle went as seen is kept by the account as a miss).
    mutating func queueWhatWasNeverSent() {
        var o = out ?? Out()
        for (id, v) in done where o.solved?[id] == nil && o.seen?[id] == nil {
            o.seen = (o.seen ?? [:]).merging([id: 1]) { a, _ in a }
            if v == 1 { unproven = (unproven ?? [:]).merging([id: 1]) { a, _ in a } }
        }
        for d in o.daily.keys { if let id = o.daily[d]?.id, o.solved?[id] == nil, o.seen?[id] == nil { o.daily[d] = nil } }
        out = o
    }

    // MARK: Kept on this device

    static let key = "puzzles.progress"
    /// One copy for each owner: the guest's under the plain key, an account's under its owner tag.
    static func key(owner: String?) -> String { owner.map { "\(key).\($0)" } ?? key }

    /// The copy of whoever is signed in now, or the guest's.
    @MainActor static func load(_ defaults: UserDefaults = .standard) -> PuzzleProgress { load(defaults, owner: Account.shared.owner) }
    @MainActor func save(_ defaults: UserDefaults = .standard) { save(defaults, owner: Account.shared.owner) }

    static func stored(_ defaults: UserDefaults, owner: String?) -> PuzzleProgress? {
        defaults.data(forKey: key(owner: owner)).flatMap { try? JSONDecoder().decode(PuzzleProgress.self, from: $0) }
    }

    static func load(_ defaults: UserDefaults, owner: String?) -> PuzzleProgress {
        guard let p = stored(defaults, owner: owner) else { return PuzzleProgress() }
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

    func save(_ defaults: UserDefaults, owner: String?) {
        if let d = try? JSONEncoder().encode(self) { defaults.set(d, forKey: Self.key(owner: owner)) }
    }

    /// Signing in on a device that has played signed out: the guest's copy joins the account's and is cleared. If the
    /// account has nothing on this device yet, the guest's copy, step and `again` included, becomes the account's.
    /// Nothing happens when there is no guest copy, so this is safe to call at every sign-in and launch.
    /// Answers whether anything joined.
    @discardableResult
    static func join(owner: String, _ defaults: UserDefaults = .standard) -> Bool {
        guard stored(defaults, owner: nil) != nil else { return false }
        var g = load(defaults, owner: nil)
        // A guest's copy never has an answer from the account: whatever it holds with nothing queued was never sent.
        g.queueWhatWasNeverSent()
        var mine: PuzzleProgress
        if stored(defaults, owner: owner) != nil {
            mine = load(defaults, owner: owner)
            mine.fold(guest: g)
        } else {
            mine = g
            mine.since = nil
        }
        mine.save(defaults, owner: owner)
        defaults.removeObject(forKey: key(owner: nil))
        return true
    }
}

/// The account's answer to a sync (GET or POST /api/chess/puzzles/progress), read leniently: a field that is missing
/// or of the wrong kind is left out, never fatal.
struct PuzzleAnswer: Equatable {
    struct Current: Equatable { var id: String; var band: Int?; var missed: Bool }
    struct Result: Equatable { var id: String; var status: String }
    struct DailyResult: Equatable { var day: Int; var status: String; var row: DailyRecord? }

    var step: Int?
    var current: Current?
    var clock: Int?
    var solved: [String] = []
    var seen: [String] = []
    var daily: [String: DailyRecord] = [:]
    var cursor: Int?
    var results: [Result] = []
    var dailyResults: [DailyResult] = []

    init() {}

    init?(_ data: Data) {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], o["ok"] as? Bool == true else { return nil }
        func int(_ v: Any?) -> Int? {
            guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue == n.doubleValue.rounded() else { return nil }
            return n.intValue
        }
        func flag(_ v: Any?) -> Bool { (v as? NSNumber)?.boolValue ?? false }
        func row(_ v: Any?) -> DailyRecord? {
            guard let r = v as? [String: Any], let id = r["id"] as? String, let on = int(r["on"]) else { return nil }
            return DailyRecord(id: id, missed: flag(r["missed"]) ? 1 : 0, on: on)
        }
        step = int(o["step"])
        clock = int(o["clock"])
        cursor = int(o["cursor"])
        if let c = o["current"] as? [String: Any], let id = c["id"] as? String { current = Current(id: id, band: int(c["band"]), missed: flag(c["missed"])) }
        solved = (o["solved"] as? [Any] ?? []).compactMap { $0 as? String }
        seen = (o["seen"] as? [Any] ?? []).compactMap { $0 as? String }
        for (d, v) in o["daily"] as? [String: Any] ?? [:] { if let n = Int(d), n >= 0, let r = row(v) { daily[String(n)] = r } }
        results = (o["results"] as? [Any] ?? []).compactMap {
            guard let r = $0 as? [String: Any], let id = r["id"] as? String, let s = r["status"] as? String else { return nil }
            return Result(id: id, status: s)
        }
        dailyResults = (o["daily_results"] as? [Any] ?? []).compactMap {
            guard let r = $0 as? [String: Any], let day = int(r["day"]), day >= 0, let s = r["status"] as? String else { return nil }
            return DailyResult(day: day, status: s, row: row(r["row"]))
        }
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
