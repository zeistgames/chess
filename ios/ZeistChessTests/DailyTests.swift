import XCTest
@testable import ZeistChess

/// Days in a row: the one rule shared with Zeist, checked against the cases both apps read, puzzles/streak-cases.json
/// (copied from Zeist with the rest of the set, bundled in the app). Every case must pass.
@MainActor
final class DailyStreakTests: XCTestCase {
    struct Cases: Decodable {
        struct Case: Decodable { let name: String; let today: Int; let daily: [String: On]; let streak: Int }
        struct On: Decodable { let on: Int }
        let window: Int
        let cases: [Case]
    }

    @MainActor func testTheSharedCases() throws {
        let url = PuzzleSet.shared.folder.appending(path: "streak-cases.json")
        let c = try JSONDecoder().decode(Cases.self, from: Data(contentsOf: url))
        XCTAssertEqual(c.window, DailyStreak.window)
        XCTAssertGreaterThan(c.cases.count, 0)
        for k in c.cases {
            let solved = Dictionary(uniqueKeysWithValues: k.daily.compactMap { e in Int(e.key).map { ($0, e.value.on) } })
            XCTAssertEqual(DailyStreak.count(today: k.today, solvedOn: solved, window: c.window), k.streak, k.name)
        }
    }

    func testCountsAndRecoverable() {
        XCTAssertTrue(DailyStreak.counts(day: 2, on: 5))
        XCTAssertFalse(DailyStreak.counts(day: 2, on: 1), "never before its own day")
        XCTAssertFalse(DailyStreak.counts(day: 2, on: 6))
        XCTAssertTrue(DailyStreak.recoverable(day: 7, today: 10))
        XCTAssertFalse(DailyStreak.recoverable(day: 6, today: 10))
        XCTAssertFalse(DailyStreak.recoverable(day: 10, today: 10), "today is not a missed day")
        XCTAssertEqual(DailyStreak.count(today: -1, solvedOn: [:]), 0, "before the start")
    }

    func testMerge() {
        let a = DailyRecord(id: "x", missed: 1, on: 4), b = DailyRecord(id: "x", missed: 0, on: 5), c = DailyRecord(id: "x", missed: 0, on: 4)
        XCTAssertEqual(DailyRecord.merge(a, b), a, "the earlier solve wins")
        XCTAssertEqual(DailyRecord.merge(b, a), a)
        XCTAssertEqual(DailyRecord.merge(a, c), a, "on the same day the one already there, never the cleaner one")
    }

    func testSolveDailyKeepsTheBestAndQueuesIt() {
        var p = PuzzleProgress()
        p.solveDaily(day: 3, id: "x", missed: true, on: 5)
        p.solveDaily(day: 3, id: "x", missed: false, on: 6)
        XCTAssertEqual(p.daily?["3"], DailyRecord(id: "x", missed: 1, on: 5))
        XCTAssertEqual(p.out?.daily["3"], DailyRecord(id: "x", missed: 1, on: 5), "kept to send later")
        p.dailyMissed = ["4": 1]
        p.solveDaily(day: 4, id: "y", missed: false, on: 4)
        XCTAssertEqual(p.daily?["4"]?.missed, 1, "a miss earlier on that day's puzzle is remembered")
        XCTAssertEqual(p.dailySolvedOn, [3: 5, 4: 4])
        let d = UserDefaults(suiteName: "daily-\(UUID())")!
        p.save(d)
        XCTAssertEqual(PuzzleProgress.load(d), p)
        d.set(Data(#"{"step":3,"done":{"a":1},"current":null}"#.utf8), forKey: PuzzleProgress.key)
        XCTAssertEqual(PuzzleProgress.load(d).step, 3, "progress saved before the daily existed still reads")
    }
}

/// The day number: whole days from the list's start to the player's own calendar date.
final class DailyCalendarTests: XCTestCase {
    func testDays() {
        let start = "2026-11-16"
        XCTAssertEqual(DailyCalendar.day(DateComponents(year: 2026, month: 11, day: 16), start: start), 0)
        XCTAssertEqual(DailyCalendar.day(DateComponents(year: 2026, month: 11, day: 20), start: start), 4)
        XCTAssertEqual(DailyCalendar.day(DateComponents(year: 2026, month: 11, day: 15), start: start), -1, "before the start")
        XCTAssertEqual(DailyCalendar.day(DateComponents(year: 2027, month: 1, day: 1), start: start), 46, "across the year")
        XCTAssertEqual(DailyCalendar.day(DateComponents(year: 2027, month: 3, day: 15), start: start), 119, "across a change of clocks")
        let back = DailyCalendar.date(of: 46, start: start)
        XCTAssertEqual([back?.year, back?.month, back?.day], [2027, 1, 1])
        XCTAssertNil(DailyCalendar.parse("2026-13-01"))
        XCTAssertEqual(DailyCalendar.say(DateComponents(year: 2026, month: 11, day: 17)), "Tuesday, November 17")
    }

    /// Midnight is the player's: a minute either side of local midnight is two different days, whatever UTC says.
    func testLocalMidnight() {
        for zone in ["Pacific/Auckland", "America/Los_Angeles", "Europe/Amsterdam"] {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: zone)!
            let midnight = cal.date(from: DateComponents(year: 2026, month: 11, day: 20))!
            XCTAssertEqual(DailyCalendar.day(at: midnight.addingTimeInterval(-60), start: "2026-11-16", calendar: cal), 3, zone)
            XCTAssertEqual(DailyCalendar.day(at: midnight.addingTimeInterval(60), start: "2026-11-16", calendar: cal), 4, zone)
        }
    }

    func testTheList() {
        let list = PuzzleDailyList(start: "2026-11-16", puzzles: [
            Puzzle(id: "a", fen: "8/8/8/8/8/8/8/K6k w - - 0 1", moves: ["a1a2", "h1h2"], mate: 0, band: 2),
            Puzzle(id: "b", fen: "8/8/8/8/8/8/8/K6k w - - 0 1", moves: ["a1a2", "h1h2"], mate: 0, band: 3),
        ])
        XCTAssertNil(list.puzzle(-1))
        XCTAssertEqual(list.puzzle(0)?.id, "a")
        XCTAssertEqual(list.puzzle(3)?.id, "b", "the list comes round")
    }

    @MainActor func testTheBundledFiles() throws {
        let set = PuzzleSet.shared
        let daily = try XCTUnwrap(set.daily)
        if let start = daily.start { XCTAssertNotNil(DailyCalendar.parse(start)) }
        XCTAssertGreaterThan(daily.puzzles.count, 0)
        XCTAssertFalse(set.themes.isEmpty)
        XCTAssertEqual(set.themes.first?.id, "forks", "in themes.json's order")
        XCTAssertNotNil(set.themeBoards["forks"], "Zeist's hand-picked board for the theme")
        for (id, b) in set.themeBoards { XCTAssertFalse(b.rings.isEmpty && b.arrows.isEmpty, "\(id) shows its idea") }
        for t in set.themes {
            let found = (1...PuzzleProgress.bands).reduce(0) { $0 + set.puzzles(of: t, band: $1).count }
            XCTAssertGreaterThan(found, 0, "\(t.id) has puzzles in this copy of the set")
        }
        XCTAssertEqual(PuzzleExtras.themes(Data("{}".utf8)), [])
        XCTAssertNil(PuzzleExtras.daily(Data(#"{"start":"2026-11-16","puzzles":[["x"]]}"#.utf8)), "one bad row refuses the list")
    }

    /// The daily waits for its start: missing or null in the file, there is no daily at all.
    @MainActor func testNoStartNoDaily() throws {
        let row = #"["OLkBj","7Q/4kpN1/4p3/3p4/5PKP/8/8/3q4 w - - 1 55","g4g5 d1g1 g5h6 g1g6",2,3]"#
        let missing = try XCTUnwrap(PuzzleExtras.daily(Data(#"{"puzzles":[\#(row)]}"#.utf8)))
        let null = try XCTUnwrap(PuzzleExtras.daily(Data(#"{"start":null,"puzzles":[\#(row)]}"#.utf8)))
        let set = try XCTUnwrap(PuzzleExtras.daily(Data(#"{"start":"2026-11-16","puzzles":[\#(row)]}"#.utf8)))
        XCTAssertNil(missing.start)
        XCTAssertNil(null.start)
        XCTAssertEqual(set.start, "2026-11-16")
        XCTAssertNil(DailyCalendar.start(of: missing))
        XCTAssertNil(DailyCalendar.today(of: missing), "no start, no daily")
        XCTAssertNil(DailyCalendar.today(of: null))
        XCTAssertNil(DailyCalendar.today(of: nil))
        // A start after today: no daily yet either.
        let later = try XCTUnwrap(PuzzleExtras.daily(Data(#"{"start":"2999-01-01","puzzles":[\#(row)]}"#.utf8)))
        XCTAssertNil(DailyCalendar.today(of: later))
    }
}

/// A theme's puzzles by the step rule.
final class ThemeSelectionTests: XCTestCase {
    private func band(_ n: Int, _ count: Int = 3) -> [Puzzle] {
        (0..<count).map { Puzzle(id: "\(n)-\($0)", fen: "8/8/8/8/8/8/8/K6k w - - 0 1", moves: ["a1a2", "h1h2"], mate: 0, band: n) }
    }

    func testTheStepsBandThenTheNearestHarderFirst() {
        var p = PuzzleProgress()
        p.step = 4 // band 3
        let bands: [Int: [Puzzle]] = [2: band(2), 3: band(3, 1), 4: band(4)]
        XCTAssertEqual(p.next(inTheme: { bands[$0] ?? [] })?.id, "3-0")
        p.done["3-0"] = 1
        XCTAssertEqual(p.next(inTheme: { bands[$0] ?? [] })?.id, "4-0", "band 3 used up: band 4 before band 2")
        p.done["4-0"] = 0
        XCTAssertEqual(p.next(inTheme: { bands[$0] ?? [] })?.id, "4-1", "seen counts as done")
        p.step = 0
        XCTAssertEqual(p.next(inTheme: { bands[$0] ?? [] })?.id, "2-0", "the step decides the band")
    }

    func testSeenPuzzlesAreNotOfferedAgain() {
        var p = PuzzleProgress()
        let one = band(1, 2)
        p.done = ["1-0": 1, "1-1": 0]
        XCTAssertNil(p.next(inTheme: { $0 == 1 ? one : [] }), "all solved or seen: the theme is done")
        XCTAssertEqual(p.done.count, 2, "looking changes nothing")
    }
}

/// Themes and the daily through the puzzle model and core's real rules, with no pauses.
@MainActor
final class PuzzleSourceTests: XCTestCase {
    var defaults: UserDefaults!

    override func setUp() async throws {
        Core.shared.boot()
        defaults = UserDefaults(suiteName: "puzzle-source-\(UUID())")!
    }

    let start = "2026-11-16"

    /// A moment on the device's own calendar.
    func local(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func solve(_ m: PuzzleModel) async {
        var n = 0
        while m.phase == .solve, let e = m.expected, n < 10 { await m.attempt(e); n += 1 }
    }

    /// A legal move other than the line's that does not mate.
    private func miss(_ m: PuzzleModel) async {
        guard let e = m.expected else { return XCTFail("no move expected") }
        for l in m.snap.legal where l.uci != e {
            let after = try? await PuzzleModel.coreRules(m.snap.fen, [l.uci])
            if after?.outcome?.reason != "checkmate" { await m.attempt(l.uci); return }
        }
    }

    func testAThemeKeepsItsOwnPuzzleInHand() async throws {
        let set = PuzzleSet.shared
        let forks = try XCTUnwrap(set.theme("forks"))
        var p = PuzzleProgress()
        p.current = .init(id: "kept", band: 1)
        p.save(defaults)
        let m = PuzzleModel(source: .theme(forks), defaults: defaults, pace: 0)
        await m.start()
        let first = try XCTUnwrap(m.puzzle)
        XCTAssertEqual(first.id, set.puzzles(of: forks, band: 1).first?.id, "the first of the step's band in the theme")
        XCTAssertEqual(ThemeInHand.load(defaults), ThemeInHand(group: "forks", id: first.id, band: first.band), "kept apart from the progress")
        XCTAssertEqual(PuzzleProgress.load(defaults).current?.id, "kept", "taking up a theme puzzle leaves current alone")
        await solve(m)
        XCTAssertEqual(m.result, .solved)
        let after = PuzzleProgress.load(defaults)
        XCTAssertEqual(after.done[first.id], 1, "a theme solve is an ordinary solve")
        XCTAssertEqual(after.step, 1, "and moves the step")
        XCTAssertEqual(after.current?.id, "kept", "the all-puzzles puzzle in hand is untouched")
        await m.next()
        XCTAssertNotEqual(m.puzzle?.id, first.id)
        XCTAssertTrue(forks.ids.contains(m.puzzle?.id ?? ""), "Next stays inside the theme")
    }

    func testADailySolveRecordsTheDay() async throws {
        let p = try XCTUnwrap(PuzzleSet.shared.daily?.puzzle(0))
        let m = PuzzleModel(source: .daily(day: 0, puzzle: p, start: start), defaults: defaults, pace: 0)
        m.clock = { self.local(2026, 11, 18, 12) }
        await m.start()
        XCTAssertFalse(m.canNext, "no Next on a day's puzzle")
        await solve(m)
        let r = PuzzleProgress.load(defaults)
        XCTAssertEqual(r.daily?["0"], DailyRecord(id: p.id, missed: 0, on: 2))
        XCTAssertEqual(r.out?.daily["0"], DailyRecord(id: p.id, missed: 0, on: 2))
        XCTAssertEqual(r.done[p.id], 1, "also an ordinary solve")
        XCTAssertNil(r.current)
    }

    /// The first finish is the day's for good (Zeist's rule since 2026-11-18): Show the move counts the day, as a miss,
    /// and a clean solve afterwards is for fun and changes nothing of the day's record.
    func testShowTheMoveCountsTheDayAsAMiss() async throws {
        let p = try XCTUnwrap(PuzzleSet.shared.daily?.puzzle(1))
        let m = PuzzleModel(source: .daily(day: 1, puzzle: p, start: start), defaults: defaults, pace: 0)
        m.clock = { self.local(2026, 11, 17, 12) }
        await m.start()
        await miss(m)
        XCTAssertTrue(m.canShow)
        await m.showMove()
        XCTAssertEqual(m.phase, .done)
        var r = PuzzleProgress.load(defaults)
        XCTAssertEqual(r.daily?["1"], DailyRecord(id: p.id, missed: 1, on: 1), "Show the move is the day's first finish")
        XCTAssertEqual(r.out?.daily["1"], DailyRecord(id: p.id, missed: 1, on: 1))
        XCTAssertEqual(r.done[p.id], 0, "the puzzle is seen")
        XCTAssertEqual(r.out?.seen?[p.id], 1, "and queued as seen")
        XCTAssertTrue(m.canRetry)
        m.clock = { self.local(2026, 11, 19, 12) }
        await m.retry()
        await solve(m)
        r = PuzzleProgress.load(defaults)
        XCTAssertEqual(r.daily?["1"], DailyRecord(id: p.id, missed: 1, on: 1), "played again, the day's record stays")
        XCTAssertEqual(r.done[p.id], 1, "the puzzle itself is solved now")
        XCTAssertNotNil(r.out?.solved?[p.id], "with its moves to send")
        // Opened again later, from the calendar: the miss is still remembered.
        let again = PuzzleModel(source: .daily(day: 1, puzzle: p, start: start), defaults: defaults, pace: 0)
        await again.start()
        XCTAssertTrue(again.missed)
    }

    /// The day a solve counts on is read when the puzzle is solved, not when the screen opened: open before midnight,
    /// solved after it, it is solved on the next day.
    func testTheDayIsReadAtTheSolve() async throws {
        let p = try XCTUnwrap(PuzzleSet.shared.daily?.puzzle(0))
        var now = local(2026, 11, 16, 23, 59)
        let m = PuzzleModel(source: .daily(day: 0, puzzle: p, start: start), defaults: defaults, pace: 0)
        m.clock = { now }
        await m.start()
        now = local(2026, 11, 17, 0, 1)
        await solve(m)
        XCTAssertEqual(PuzzleProgress.load(defaults).daily?["0"]?.on, 1)
    }

    // One solve counts once, wherever it happens.

    private func onlyTheme(_ p: Puzzle) -> PuzzleTheme { PuzzleTheme(id: "only", name: "Only", count: 1, bands: [p.band: [p.id]]) }

    func testThemeThenMain() async throws {
        let main = PuzzleModel(defaults: defaults, pace: 0)
        await main.start()
        let p = try XCTUnwrap(main.puzzle)
        let theme = PuzzleModel(source: .theme(onlyTheme(p)), defaults: defaults, pace: 0)
        await theme.start()
        XCTAssertEqual(theme.puzzle?.id, p.id)
        await solve(theme)
        XCTAssertEqual(PuzzleProgress.load(defaults).step, 1)
        // Solved on the main screen as well before it moved on: not counted again.
        await solve(main)
        XCTAssertEqual(main.phase, .done)
        XCTAssertEqual(PuzzleProgress.load(defaults).step, 1, "the step moves once")
    }

    func testMainMovesOnFromAPuzzleSolvedElsewhere() async throws {
        let main = PuzzleModel(defaults: defaults, pace: 0)
        await main.start()
        let p = try XCTUnwrap(main.puzzle)
        let theme = PuzzleModel(source: .theme(onlyTheme(p)), defaults: defaults, pace: 0)
        await theme.start()
        await solve(theme)
        await main.moveOnIfDoneElsewhere()
        XCTAssertNotEqual(main.puzzle?.id, p.id, "the main screen goes on to its next puzzle")
        XCTAssertEqual(PuzzleProgress.load(defaults).step, 1)
    }

    func testDailyThenMain() async throws {
        let main = PuzzleModel(defaults: defaults, pace: 0)
        await main.start()
        let p = try XCTUnwrap(main.puzzle)
        let daily = PuzzleModel(source: .daily(day: 0, puzzle: p, start: start), defaults: defaults, pace: 0)
        daily.clock = { self.local(2026, 11, 16, 12) }
        await daily.start()
        await solve(daily)
        XCTAssertEqual(PuzzleProgress.load(defaults).step, 1)
        XCTAssertNotNil(PuzzleProgress.load(defaults).daily?["0"])
        await solve(main)
        XCTAssertEqual(PuzzleProgress.load(defaults).step, 1, "the step moves once")
    }

    func testMainThenTheme() async throws {
        let main = PuzzleModel(defaults: defaults, pace: 0)
        await main.start()
        let p = try XCTUnwrap(main.puzzle)
        await solve(main)
        XCTAssertEqual(PuzzleProgress.load(defaults).step, 1)
        let theme = PuzzleModel(source: .theme(onlyTheme(p)), defaults: defaults, pace: 0)
        await theme.start()
        XCTAssertNil(theme.puzzle, "a solved puzzle is not offered in a theme")
        XCTAssertEqual(theme.line, "You have done every puzzle in Only.")
        await theme.begin(p)
        await solve(theme)
        XCTAssertEqual(theme.phase, .done)
        XCTAssertEqual(PuzzleProgress.load(defaults).step, 1, "played again, not counted again")
    }
}
