import XCTest
@testable import ZeistChess

/// A stand-in for Zeist's account (POST /api/chess/puzzles/progress), following docs/PUZZLE-PROGRESS.md there: solves
/// are a union and need their moves, the first daily row for a day is kept for good and only for a finished puzzle,
/// step and the puzzle in hand go to the higher clock, and the cursor moves with each change.
@MainActor
final class FakeZeist {
    var solved: [String: Int] = [:]      // id to the cursor it changed at
    var seen: [String: Int] = [:]
    var daily: [Int: (row: DailyRecord, at: Int)] = [:]
    var step = 0
    var current: [String: Any]?
    var clock = 0
    var cursor = 100
    var requests: [[String: Any]] = []
    /// Solves put off ("later"), refused ("wrong"), and a limit on the day numbers taken.
    var later: Set<String> = []
    var wrong: Set<String> = []
    var newestDay = 1000
    /// The day's puzzle, where a test names one: a row for that day with another id is "wrong".
    var dayPuzzle: [Int: String] = [:]
    var owner = "o1"
    var status = 200
    /// Runs while a request is out, before the answer is made.
    var during: (@MainActor () -> Void)?

    func handle(_ body: Data, _ token: String) -> (Data, Int) {
        let b = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        requests.append(b)
        during?()
        if status != 200 { return (Data(#"{"ok":false,"error":"unavailable"}"#.utf8), status) }
        if b["owner"] as? String != owner { return (Data(#"{"ok":false,"error":"owner"}"#.utf8), 403) }
        let since = b["since"] as? Int ?? 0
        cursor += 1
        var results: [[String: Any]] = [], dailyResults: [[String: Any]] = []
        var counted: Set<String> = []
        for s in b["solved"] as? [[String: Any]] ?? [] {
            let id = s["id"] as! String, moves = s["moves"] as? [String] ?? []
            if later.contains(id) { results.append(["id": id, "status": "later"]); continue }
            if wrong.contains(id) || moves.isEmpty { results.append(["id": id, "status": "wrong"]); continue }
            if solved[id] == nil { solved[id] = cursor; seen[id] = nil }
            counted.insert(id)
            results.append(["id": id, "status": "solved"])
        }
        for id in b["seen"] as? [String] ?? [] {
            if solved[id] == nil, seen[id] == nil { seen[id] = cursor }
            results.append(["id": id, "status": "seen"])
        }
        let sentSolves = Set((b["solved"] as? [[String: Any]] ?? []).map { $0["id"] as! String })
        for r in b["daily"] as? [[String: Any]] ?? [] {
            let day = r["day"] as! Int, id = r["id"] as! String, on = r["on"] as! Int, missed = r["missed"] as! Int
            // As src/chessPuzzles.ts: out of range or not the day's puzzle is "wrong"; then the puzzle must be finished
            // on the account ("unsolved"), and only then is a day already kept answered with the row kept.
            guard day >= 0, on >= day, on <= newestDay, dayPuzzle[day] == nil || dayPuzzle[day] == id else { dailyResults.append(["day": day, "status": "wrong"]); continue }
            let finished = (solved[id] != nil || seen[id] != nil) && !(sentSolves.contains(id) && !counted.contains(id))
            guard finished else { dailyResults.append(["day": day, "status": "unsolved"]); continue }
            if let kept = daily[day] {
                dailyResults.append(["day": day, "status": "kept", "row": ["id": kept.row.id, "missed": kept.row.missed, "on": kept.row.on]])
                continue
            }
            let row = DailyRecord(id: id, missed: solved[id] == nil ? 1 : missed, on: on)
            daily[day] = (row, cursor)
            dailyResults.append(["day": day, "status": "kept", "row": ["id": row.id, "missed": row.missed, "on": row.on]])
        }
        if let c = b["clock"] as? Int, c > clock {
            clock = c
            step = b["step"] as? Int ?? step
            current = (b["current"] as? [String: Any]).map { ["id": $0["id"]!, "band": 3, "missed": $0["missed"] ?? false] }
        }
        var a: [String: Any] = ["ok": true, "set": "t", "step": step, "clock": clock, "cursor": cursor,
                                "solved": solved.filter { $0.value > since }.keys.sorted(), "seen": seen.filter { $0.value > since }.keys.sorted(),
                                "results": results, "daily_results": dailyResults, "solved_count": solved.count]
        a["current"] = current ?? NSNull()
        a["daily"] = Dictionary(uniqueKeysWithValues: daily.filter { $0.value.at > since }.map { (String($0.key), ["id": $0.value.row.id, "missed": $0.value.row.missed, "on": $0.value.row.on] as [String: Any]) })
        return (try! JSONSerialization.data(withJSONObject: a), 200)
    }
}

@MainActor
final class PuzzleSyncTests: XCTestCase {
    private var zeist: FakeZeist!

    override func setUp() { zeist = FakeZeist() }

    /// One device signed in to the account: its own storage and its own sync.
    private func device(owner: String? = "o1") -> (UserDefaults, PuzzleSync) {
        let d = UserDefaults(suiteName: "puzzle-sync-\(UUID())")!
        let s = PuzzleSync(defaults: d)
        let z = zeist!
        s.send = { body, token in z.handle(body, token) }
        s.who = { owner.map { ("token", $0) } }
        return (d, s)
    }

    private func change(_ d: UserDefaults, owner: String? = "o1", _ f: (inout PuzzleProgress) -> Void) {
        var p = PuzzleProgress.load(d, owner: owner)
        f(&p)
        p.save(d, owner: owner)
    }

    // MARK: What a device queues

    func testEveryFinishIsQueuedWithItsProofAndMovesTheClock() {
        var p = PuzzleProgress()
        p.take(.init(id: "aaaaa", band: 1))
        XCTAssertEqual(p.clock, 1, "taking a puzzle up")
        p.take(.init(id: "aaaaa", band: 1, missed: true))
        XCTAssertEqual(p.clock, 2, "its first miss")
        p.take(.init(id: "aaaaa", band: 1, missed: true))
        XCTAssertEqual(p.clock, 2, "nothing changed")
        p.finish("aaaaa", .missed, moves: "e2e4 d2d4")
        XCTAssertEqual(p.clock, 3)
        XCTAssertEqual(p.out?.solved, ["aaaaa": "e2e4 d2d4"], "the solver's moves as played are the proof")
        p.finish("bbbbb", .shown)
        XCTAssertEqual(p.out?.seen, ["bbbbb": 1], "Show the move is seen, with no proof")
        p.take(.init(id: "ccccc", band: 1))
        let before = p.clock
        p.skip("ccccc")
        XCTAssertEqual(p.out?.seen, ["bbbbb": 1], "Next on an unfinished puzzle sends nothing: leaving is not seeing the answer")
        XCTAssertEqual(p.done["ccccc"], 0, "it is seen on this device")
        XCTAssertNil(p.current)
        XCTAssertEqual(p.clock, (before ?? 0) + 1)
        let o = p.outgoing()
        XCTAssertEqual(o.solved.map(\.id), ["aaaaa"])
        XCTAssertEqual(o.solved.first?.moves, ["e2e4", "d2d4"])
        XCTAssertEqual(o.seen, ["bbbbb"])
    }

    func testOneRequestCarriesAtMostAHundredAndSkipsWhatWasPutOff() {
        var p = PuzzleProgress()
        for i in 0..<150 { p.finish(String(format: "p%04d", i), .solved, moves: "a2a3") }
        p.solveDaily(day: 2, id: "p0001", missed: false, on: 2)
        XCTAssertEqual(p.outgoing().solved.count, 100)
        XCTAssertTrue(p.outgoing().daily.isEmpty, "no room left in this request")
        let o = p.outgoing(max: 100, skip: Set((0..<100).map { String(format: "p%04d", $0) }))
        XCTAssertEqual(o.solved.count, 50)
        XCTAssertEqual(o.daily.map(\.day), [2])
        XCTAssertTrue(p.outgoing(skip: ["day:2"]).daily.isEmpty)
    }

    // MARK: A sync

    func testASyncSendsTheQueueAndTakesTheAccountsProgress() async {
        let (d, sync) = device()
        zeist.solved = ["zzzzz": 50]
        zeist.seen = ["yyyyy": 50]
        change(d) { p in
            p.finish("aaaaa", .solved, moves: "e2e4")
            p.finish("bbbbb", .shown)
        }
        let ok = await sync.sync()
        XCTAssertTrue(ok)
        let sent = zeist.requests[0]
        XCTAssertEqual(sent["owner"] as? String, "o1")
        XCTAssertEqual(sent["clock"] as? Int, 2)
        XCTAssertEqual((sent["solved"] as? [[String: Any]])?.first?["moves"] as? [String], ["e2e4"])
        XCTAssertEqual(sent["seen"] as? [String], ["bbbbb"])
        let p = PuzzleProgress.load(d, owner: "o1")
        XCTAssertEqual(p.done, ["aaaaa": 1, "bbbbb": 0, "zzzzz": 1, "yyyyy": 0], "solved and seen are unions")
        XCTAssertTrue(p.outgoing().isEmpty, "everything answered has left the queue")
        XCTAssertEqual(p.since, zeist.cursor)
        XCTAssertEqual(zeist.solved.keys.sorted(), ["aaaaa", "zzzzz"])
        XCTAssertEqual(sync.changes, 1)
        // Nothing changed since: the next sync sends an empty queue and changes nothing here.
        _ = await sync.sync()
        XCTAssertEqual((zeist.requests[1]["solved"] as? [Any])?.count, 0)
        XCTAssertEqual(zeist.requests[1]["since"] as? Int, p.since)
    }

    func testAQueueLongerThanOneRequestGoesOutInSeveral() async {
        let (d, sync) = device()
        change(d) { p in for i in 0..<230 { p.finish(String(format: "p%04d", i), .solved, moves: "a2a3") } }
        _ = await sync.sync()
        XCTAssertEqual(zeist.requests.count, 3)
        XCTAssertEqual(zeist.solved.count, 230)
        XCTAssertTrue(PuzzleProgress.load(d, owner: "o1").outgoing().isEmpty)
    }

    func testASolvePutOffStaysQueuedAndTheRestStillGoes() async {
        let (d, sync) = device()
        zeist.later = ["aaaaa"]
        zeist.wrong = ["ccccc"]
        change(d) { p in
            p.finish("aaaaa", .solved, moves: "e2e4")
            p.finish("bbbbb", .solved, moves: "e2e4")
            p.finish("ccccc", .solved, moves: "e2e4")
        }
        _ = await sync.sync()
        let p = PuzzleProgress.load(d, owner: "o1")
        XCTAssertEqual(p.out?.solved, ["aaaaa": "e2e4"], "put off: kept for a later day; refused: gone from the queue")
        XCTAssertEqual(p.done["ccccc"], 1, "a refused solve stays solved on the device")
        XCTAssertEqual(zeist.seen.keys.sorted(), ["ccccc"], "and goes to the account as seen, so the puzzle is finished there")
        XCTAssertNil(p.out?.seen?["ccccc"])
        XCTAssertEqual(zeist.requests.count, 2, "the one put off is not sent again in the same sync")
        XCTAssertEqual((zeist.requests[1]["solved"] as? [Any])?.count, 0)
    }

    func testNothingIsSentSignedOutAndAFailedRequestKeepsEverything() async {
        let (guest, quiet) = device(owner: nil)
        change(guest, owner: nil) { $0.finish("aaaaa", .solved, moves: "e2e4") }
        let sent = await quiet.sync()
        XCTAssertFalse(sent)
        XCTAssertTrue(zeist.requests.isEmpty)
        let (d, sync) = device()
        change(d) { $0.finish("aaaaa", .solved, moves: "e2e4") }
        zeist.status = 503
        let ok = await sync.sync()
        XCTAssertFalse(ok)
        XCTAssertEqual(PuzzleProgress.load(d, owner: "o1").out?.solved, ["aaaaa": "e2e4"])
        XCTAssertEqual(sync.changes, 0)
    }

    func testProgressQueuedForAnotherAccountIsRefusedAndKept() async {
        let (d, sync) = device(owner: "o2")
        change(d, owner: "o2") { $0.finish("aaaaa", .solved, moves: "e2e4") }
        let ok = await sync.sync()
        XCTAssertFalse(ok, "Zeist answers 403 owner")
        XCTAssertEqual(PuzzleProgress.load(d, owner: "o2").out?.solved, ["aaaaa": "e2e4"])
        XCTAssertTrue(zeist.solved.isEmpty)
    }

    // MARK: Step and the puzzle in hand

    func testTheHigherClockWinsAndAChangeDuringTheRequestKeepsTheDevices() async {
        let (a, syncA) = device(), (b, syncB) = device()
        change(a) { p in for i in 0..<5 { p.finish("a000\(i)", .solved, moves: "e2e4") } }   // step 5, clock 5
        _ = await syncA.sync()
        _ = await syncB.sync()
        var pb = PuzzleProgress.load(b, owner: "o1")
        XCTAssertEqual([pb.step, pb.clock ?? -1], [5, 5], "the other device takes the account's step")
        XCTAssertEqual(pb.done.count, 5)
        // B finishes one while its request is out: the answer does not undo it.
        change(b) { $0.take(.init(id: "b0001", band: 3)) }
        zeist.during = { [unowned self] in
            self.zeist.during = nil
            self.change(b) { $0.finish("b0001", .shown) }
        }
        _ = await syncB.sync()
        pb = PuzzleProgress.load(b, owner: "o1")
        XCTAssertEqual(pb.step, 3, "down two after Show the move, kept")
        XCTAssertNil(pb.current)
        XCTAssertTrue(pb.outgoing().isEmpty, "and the pass asked for during the request sent it")
        XCTAssertEqual(zeist.step, 3)
        _ = await syncA.sync()
        XCTAssertEqual(PuzzleProgress.load(a, owner: "o1").step, 3)
    }

    func testAPuzzleInHandAlreadyFinishedHereIsNotTakenUpAgain() {
        var p = PuzzleProgress()
        p.done = ["aaaaa": 1]
        var a = PuzzleAnswer()
        a.step = 4; a.clock = 9; a.current = .init(id: "aaaaa", band: 2, missed: false)
        p.merge(a, sent: 0)
        XCTAssertNil(p.current)
        XCTAssertEqual([p.step, p.clock ?? -1], [4, 9])
        a.current = .init(id: "bbbbb", band: 2, missed: true)
        a.clock = 10
        p.merge(a, sent: 9)
        XCTAssertEqual(p.current, .init(id: "bbbbb", band: 2, missed: true))
    }

    // MARK: The daily, both ways

    func testTheDailySolvedOnOneDeviceShowsOnTheOtherBothWays() async {
        let (a, syncA) = device(), (b, syncB) = device()
        // Day 0 on A, clean.
        change(a) { p in
            p.solveDaily(day: 0, id: "d0000", missed: false, on: 0)
            p.finish("d0000", .solved, moves: "e2e4")
        }
        _ = await syncA.sync()
        _ = await syncB.sync()
        XCTAssertEqual(PuzzleProgress.load(b, owner: "o1").daily?["0"], DailyRecord(id: "d0000", missed: 0, on: 0))
        XCTAssertEqual(PuzzleProgress.load(b, owner: "o1").done["d0000"], 1)
        // Day 1 on B, by Show the move: a miss.
        change(b) { p in
            p.solveDaily(day: 1, id: "d0001", missed: true, on: 1)
            p.finish("d0001", .shown)
        }
        _ = await syncB.sync()
        _ = await syncA.sync()
        let pa = PuzzleProgress.load(a, owner: "o1")
        XCTAssertEqual(pa.daily?["1"], DailyRecord(id: "d0001", missed: 1, on: 1))
        XCTAssertEqual(pa.dailySolvedOn, [0: 0, 1: 1])
        XCTAssertEqual(DailyStreak.count(today: 1, solvedOn: pa.dailySolvedOn), 2)
        // A plays day 1 too, clean and later, before hearing of B's: the account's first row stays the day's.
        let (c, syncC) = device()
        change(c) { p in
            p.solveDaily(day: 1, id: "d0001", missed: false, on: 2)
            p.finish("d0001", .solved, moves: "e2e4")
        }
        _ = await syncC.sync()
        let pc = PuzzleProgress.load(c, owner: "o1")
        XCTAssertEqual(pc.daily?["1"], DailyRecord(id: "d0001", missed: 1, on: 1), "the row the account keeps takes this device's place")
        XCTAssertTrue(pc.outgoing().isEmpty)
    }

    func testADailyRowWaitsForItsSolveAndARefusedDayIsNotShownAsDone() async {
        let (d, sync) = device()
        zeist.later = ["d0003"]
        zeist.newestDay = 5
        change(d) { p in
            p.solveDaily(day: 3, id: "d0003", missed: false, on: 3)
            p.finish("d0003", .solved, moves: "e2e4")
            p.solveDaily(day: 9, id: "d0009", missed: false, on: 9)   // a clock set ahead
            p.finish("d0009", .solved, moves: "e2e4")
        }
        _ = await sync.sync()
        var p = PuzzleProgress.load(d, owner: "o1")
        XCTAssertNotNil(p.out?.daily["3"], "its solve was put off, so the row stays queued with it")
        XCTAssertNotNil(p.daily?["3"])
        XCTAssertNil(p.daily?["9"], "refused: the day can be played when it comes")
        XCTAssertNil(p.out?.daily["9"])
        zeist.later = []
        _ = await sync.sync()
        p = PuzzleProgress.load(d, owner: "o1")
        XCTAssertNil(p.out?.daily["3"])
        XCTAssertEqual(zeist.daily[3]?.row, DailyRecord(id: "d0003", missed: 0, on: 3))
    }

    // MARK: Signing in on a device that has played signed out

    func testTheGuestsProgressBecomesTheAccountsWhenItHasNoneHere() async {
        let (d, sync) = device()
        change(d, owner: nil) { p in
            for i in 0..<3 { p.finish("g000\(i)", .solved, moves: "e2e4") }
            p.finish("g0009", .shown)
            p.solveDaily(day: 0, id: "g0000", missed: false, on: 0)
            p.again = ["g0000": 1]
        }
        XCTAssertTrue(PuzzleProgress.join(owner: "o1", d))
        XCTAssertNil(PuzzleProgress.stored(d, owner: nil), "the guest's copy is cleared")
        XCTAssertFalse(PuzzleProgress.join(owner: "o1", d), "and joining again does nothing")
        let p = PuzzleProgress.load(d, owner: "o1")
        XCTAssertEqual(p.step, 1, "the guest's step: three up, two down")
        XCTAssertEqual(p.again, ["g0000": 1])
        _ = await sync.sync()
        XCTAssertEqual(zeist.solved.count, 3, "the guest's solves are checked and counted like any other")
        XCTAssertEqual(zeist.seen.keys.sorted(), ["g0009"])
        XCTAssertEqual(zeist.daily[0]?.row, DailyRecord(id: "g0000", missed: 0, on: 0))
    }

    func testTheGuestsProgressFoldsIntoAnAccountAlreadyHere() {
        let d = UserDefaults(suiteName: "puzzle-sync-\(UUID())")!
        var mine = PuzzleProgress()
        mine.step = 9
        mine.clock = 40
        mine.done = ["m0001": 1, "both1": 0]
        mine.daily = ["0": DailyRecord(id: "d0000", missed: 1, on: 0), "1": DailyRecord(id: "d0001", missed: 0, on: 3)]
        mine.out = .init(daily: ["1": DailyRecord(id: "d0001", missed: 0, on: 3)], solved: nil, seen: nil)
        mine.again = ["m0001": 1]
        mine.save(d, owner: "o1")
        var g = PuzzleProgress()
        g.finish("both1", .solved, moves: "e2e4")
        g.finish("g0001", .shown)
        g.solveDaily(day: 0, id: "d0000", missed: false, on: 0)   // the account already has day 0 from Zeist
        g.solveDaily(day: 1, id: "d0001", missed: true, on: 1)    // earlier than the account's unsent row
        g.solveDaily(day: 2, id: "d0002", missed: false, on: 2)
        for id in ["d0000", "d0001", "d0002"] { g.finish(id, .solved, moves: "e2e4") }
        g.again = ["zzzzz": 1]
        g.save(d, owner: nil)
        XCTAssertTrue(PuzzleProgress.join(owner: "o1", d))
        let p = PuzzleProgress.load(d, owner: "o1")
        XCTAssertEqual([p.step, p.clock ?? -1], [9, 40], "the account keeps its own step")
        XCTAssertEqual(p.again, ["m0001": 1], "and its own round")
        XCTAssertEqual(p.done, ["m0001": 1, "both1": 1, "g0001": 0, "d0000": 1, "d0001": 1, "d0002": 1], "a union, solved winning")
        XCTAssertEqual(p.out?.solved?.keys.sorted(), ["both1", "d0000", "d0001", "d0002"])
        XCTAssertEqual(p.out?.seen, ["g0001": 1])
        XCTAssertEqual(p.daily?["0"], DailyRecord(id: "d0000", missed: 1, on: 0), "a day the account has from Zeist stays the account's")
        XCTAssertEqual(p.daily?["1"], DailyRecord(id: "d0001", missed: 1, on: 1), "an unsent day goes to the earlier finish")
        XCTAssertEqual(p.out?.daily["1"], DailyRecord(id: "d0001", missed: 1, on: 1))
        XCTAssertEqual(p.daily?["2"], DailyRecord(id: "d0002", missed: 0, on: 2))
    }

    /// A build before this one kept one copy for the whole device, with no proof of its solves and nothing queued.
    func testSolvesKeptWithoutProofGoAsSeenUntilTheyAreSolvedAgain() async {
        let (d, sync) = device()
        let old = #"{"step":6,"done":{"s0001":1,"s0002":1,"n0001":0},"current":null,"daily":{"0":{"id":"s0001","missed":0,"on":0}},"out":{"daily":{"0":{"id":"s0001","missed":0,"on":0}}}}"#
        d.set(Data(old.utf8), forKey: PuzzleProgress.key)
        XCTAssertTrue(PuzzleProgress.join(owner: "o1", d))
        var p = PuzzleProgress.load(d, owner: "o1")
        XCTAssertEqual(p.done, ["s0001": 1, "s0002": 1, "n0001": 0], "they stay solved on this device")
        XCTAssertEqual(p.unproven, ["s0001": 1, "s0002": 1])
        XCTAssertEqual(p.step, 6)
        _ = await sync.sync()
        XCTAssertTrue(zeist.solved.isEmpty, "the account counts no solve without its moves")
        XCTAssertEqual(zeist.seen.keys.sorted(), ["n0001", "s0001", "s0002"])
        XCTAssertEqual(zeist.daily[0]?.row, DailyRecord(id: "s0001", missed: 1, on: 0), "a day whose puzzle went as seen is kept as a miss")
        p = PuzzleProgress.load(d, owner: "o1")
        XCTAssertEqual(p.done["s0001"], 1)
        XCTAssertEqual(p.daily?["0"], DailyRecord(id: "s0001", missed: 1, on: 0), "and the device shows the day as the account keeps it")
        XCTAssertTrue(p.outgoing().isEmpty)
        // Solved again in a later round, it goes with its proof and counts.
        change(d) { p in XCTAssertFalse(p.replayFinish("s0002", .solved, moves: "e2e4"), "done does not change: it was solved here already") }
        XCTAssertEqual(PuzzleProgress.load(d, owner: "o1").out?.solved, ["s0002": "e2e4"])
        _ = await sync.sync()
        XCTAssertEqual(zeist.solved.keys.sorted(), ["s0002"])
        p = PuzzleProgress.load(d, owner: "o1")
        XCTAssertEqual(p.unproven, ["s0001": 1], "proven now")
        // A puzzle solved and proven is not queued again by a replay.
        change(d) { $0.replayFinish("s0002", .solved, moves: "e2e4") }
        XCTAssertNil(PuzzleProgress.load(d, owner: "o1").out?.solved?["s0002"])
    }

    /// A guest's valid day whose puzzle is in `done` with nothing queued for it (an older copy) still goes.
    func testAGuestsDayGoesWithItsPuzzleSeen() {
        var g = PuzzleProgress()
        g.done = ["d0000": 0]
        g.daily = ["0": DailyRecord(id: "d0000", missed: 1, on: 0)]
        g.out = .init(daily: ["0": DailyRecord(id: "d0000", missed: 1, on: 0), "1": DailyRecord(id: "ghost", missed: 0, on: 1)], solved: nil, seen: nil)
        g.queueWhatWasNeverSent()
        XCTAssertEqual(g.out?.seen, ["d0000": 1])
        XCTAssertNotNil(g.out?.daily["0"])
        XCTAssertNil(g.out?.daily["1"], "a row whose puzzle was never finished here is not sent")
    }

    /// Show the move, the sync goes out, and the player solves it on Retry before the answer is back: the answer to
    /// "seen" must not take the queued solve with it.
    func testASolveMadeWhileItsSeenIsOutIsNotLost() async {
        let (d, sync) = device()
        change(d) { $0.finish("aaaaa", .shown) }
        zeist.during = { [unowned self] in
            self.zeist.during = nil
            self.change(d) { $0.replayFinish("aaaaa", .solved, moves: "e2e4", round: false) }
        }
        _ = await sync.sync()
        XCTAssertEqual(zeist.solved.keys.sorted(), ["aaaaa"], "the solve went in the next request")
        let p = PuzzleProgress.load(d, owner: "o1")
        XCTAssertTrue(p.outgoing().isEmpty)
        XCTAssertEqual(p.done["aaaaa"], 1)
    }

    func testASolveSentWithOtherMovesStaysQueued() {
        var p = PuzzleProgress()
        p.finish("aaaaa", .solved, moves: "e2e4")
        let sent = p.outgoing()
        p.out?.solved?["aaaaa"] = "d2d4"
        var a = PuzzleAnswer()
        a.results = [.init(id: "aaaaa", status: "solved")]
        p.settle(a, sent: sent)
        XCTAssertEqual(p.out?.solved, ["aaaaa": "d2d4"])
        a.results = [.init(id: "zzzzz", status: "seen")]
        p.out?.seen = ["zzzzz": 1]
        p.settle(a, sent: sent)
        XCTAssertEqual(p.out?.seen, ["zzzzz": 1], "an answer for something this request did not carry settles nothing")
    }

    /// A day's solve the account refuses: the puzzle goes as seen, so the day settles (as a miss) and is not asked
    /// about on every sync from then on.
    func testADayWhoseSolveIsRefusedSettlesAsAMiss() async {
        let (d, sync) = device()
        zeist.wrong = ["d0004"]
        change(d) { p in
            p.solveDaily(day: 4, id: "d0004", missed: false, on: 4)
            p.finish("d0004", .solved, moves: "e2e4")
        }
        _ = await sync.sync()
        let p = PuzzleProgress.load(d, owner: "o1")
        XCTAssertTrue(p.outgoing().isEmpty)
        XCTAssertEqual(zeist.daily[4]?.row, DailyRecord(id: "d0004", missed: 1, on: 4))
        XCTAssertEqual(p.daily?["4"], DailyRecord(id: "d0004", missed: 1, on: 4))
        XCTAssertEqual(p.done["d0004"], 1, "still solved on this device")
    }

    func testARowThatIsNotTheDaysPuzzleIsRefused() async {
        let (d, sync) = device()
        zeist.dayPuzzle = [2: "right"]
        change(d) { p in
            p.solveDaily(day: 2, id: "other", missed: false, on: 2)
            p.finish("other", .solved, moves: "e2e4")
        }
        _ = await sync.sync()
        let p = PuzzleProgress.load(d, owner: "o1")
        XCTAssertNil(p.daily?["2"])
        XCTAssertTrue(p.outgoing().isEmpty)
        XCTAssertEqual(p.done["other"], 1)
    }

    /// The guest's row wins the day but was never queued: the account's own queued row for that day is left alone.
    func testAGuestRowNeverQueuedDoesNotRemoveTheAccountsQueuedRow() {
        var mine = PuzzleProgress()
        mine.daily = ["1": DailyRecord(id: "d0001", missed: 0, on: 3)]
        mine.out = .init(daily: ["1": DailyRecord(id: "d0001", missed: 0, on: 3)], solved: nil, seen: nil)
        var g = PuzzleProgress()
        g.daily = ["1": DailyRecord(id: "d0001", missed: 1, on: 1)]
        mine.fold(guest: g)
        XCTAssertEqual(mine.daily?["1"], DailyRecord(id: "d0001", missed: 1, on: 1))
        XCTAssertEqual(mine.out?.daily["1"], DailyRecord(id: "d0001", missed: 0, on: 3))
    }

    func testAQueuedSolveIsNeverAlsoSentAsSeenAfterAJoin() {
        var mine = PuzzleProgress()
        mine.finish("aaaaa", .shown)
        var g = PuzzleProgress()
        g.finish("aaaaa", .solved, moves: "e2e4")
        mine.fold(guest: g)
        XCTAssertEqual(mine.out?.solved, ["aaaaa": "e2e4"])
        XCTAssertNil(mine.out?.seen?["aaaaa"])
        XCTAssertEqual(mine.done["aaaaa"], 1)
    }

    func testEachOwnerHasACopyOfTheirOwn() {
        let d = UserDefaults(suiteName: "puzzle-sync-\(UUID())")!
        change(d, owner: "o1") { $0.finish("aaaaa", .solved, moves: "e2e4") }
        change(d, owner: "o2") { $0.finish("bbbbb", .solved, moves: "e2e4") }
        XCTAssertEqual(PuzzleProgress.load(d, owner: "o1").done, ["aaaaa": 1])
        XCTAssertEqual(PuzzleProgress.load(d, owner: "o2").done, ["bbbbb": 1])
        XCTAssertEqual(PuzzleProgress.load(d, owner: nil).done, [:], "signed out, a guest starts their own")
    }

    func testAnAnswerIsReadLeniently() {
        XCTAssertNil(PuzzleAnswer(Data(#"{"ok":false,"error":"signin"}"#.utf8)))
        let a = PuzzleAnswer(Data(#"{"ok":true,"step":"x","clock":3,"cursor":1794612345678,"current":{"id":"Gdz7L","band":4,"missed":false},"solved":["a",1],"daily":{"3":{"id":"Mk3M5","missed":true,"on":4},"x":{"id":"q","on":1},"4":{"id":"q"}},"daily_results":[{"day":3,"status":"kept","row":{"id":"Mk3M5","missed":1,"on":5}},{"day":"x","status":"kept"}]}"#.utf8))
        XCTAssertNotNil(a)
        XCTAssertNil(a?.step)
        XCTAssertEqual(a?.cursor, 1_794_612_345_678)
        XCTAssertEqual(a?.solved, ["a"])
        XCTAssertEqual(a?.daily, ["3": DailyRecord(id: "Mk3M5", missed: 1, on: 4)])
        XCTAssertEqual(a?.dailyResults, [.init(day: 3, status: "kept", row: DailyRecord(id: "Mk3M5", missed: 1, on: 5))])
    }
}
