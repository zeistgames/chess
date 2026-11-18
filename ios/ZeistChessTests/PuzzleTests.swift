import XCTest
@testable import ZeistChess

/// The loader: the one place that knows the file format.
final class PuzzleDataTests: XCTestCase {
    func testIndex() {
        let d = Data(#"{"source":"x","bands":[{"band":2,"rating":[900,1099],"count":1,"files":["2-b.json"]},{"band":1,"files":["1-a.json","../up.json"]},{"band":"x"}]}"#.utf8)
        let bands = PuzzleData.index(d)
        XCTAssertEqual(bands.map(\.band), [1, 2])
        XCTAssertEqual(bands[0].files, ["1-a.json"], "paths outside the folder are dropped")
        XCTAssertEqual(PuzzleData.index(Data("not json".utf8)), [])
        XCTAssertEqual(PuzzleData.index(Data("{}".utf8)), [])
    }

    func testRowsAndSkippedRows() {
        let d = Data("""
        {"band":1,"puzzles":[
          ["Gdz7L","8/5pk1/4p1p1/3p4/3N4/r1p4R/5PKP/8 w - - 3 44","d4b5 c3c2 h3a3 c2c1q",0],
          ["RW8uC","r2r2Qk/pp4bp/n1b3pN/4p3/P3p3/2P4P/1P3PPB/R3R1K1 b - - 6 24","d8g8 h6f7",1],
          ["odd","8/8/8/8/8/8/8/K6k w - - 0 1","a1a2 h1h2 a2a3",0],
          ["baduci","8/8/8/8/8/8/8/K6k w - - 0 1","a1a2 h1z2",0],
          ["boolmate","8/8/8/8/8/8/8/K6k w - - 0 1","a1a2 h1h2",true],
          ["badfen","8/8/8 w - - 0 1","a1a2 h1h2",0],
          ["nofen",5,"a1a2 h1h2",0],
          ["short"],
          "not a row",
          ["","8/8/8/8/8/8/8/K6k w - - 0 1","a1a2 h1h2",0],
          ["neg","8/8/8/8/8/8/8/K6k w - - 0 1","a1a2 h1h2",-1]
        ]}
        """.utf8)
        let p = PuzzleData.puzzles(d, band: 1)
        XCTAssertEqual(p.map(\.id), ["Gdz7L", "RW8uC"])
        XCTAssertEqual(p[0].moves, ["d4b5", "c3c2", "h3a3", "c2c1q"])
        XCTAssertEqual(p[0].solver, "b", "White moves first, so the solver is Black")
        XCTAssertEqual(p[1].solver, "w")
        XCTAssertEqual(p[1].mate, 1)
        XCTAssertEqual(p[1].band, 1)
        XCTAssertEqual(PuzzleData.puzzles(Data("[]".utf8), band: 1), [])
        XCTAssertEqual(PuzzleData.puzzles(Data(#"{"band":1}"#.utf8), band: 1), [])
    }

    func testUCI() {
        XCTAssertTrue(PuzzleData.isUCI("e2e4"))
        XCTAssertTrue(PuzzleData.isUCI("e7e8n"))
        XCTAssertFalse(PuzzleData.isUCI("e7e8k"))
        XCTAssertFalse(PuzzleData.isUCI("e9e4"))
        XCTAssertFalse(PuzzleData.isUCI("e2"))
    }

    /// The copy in the app: eight bands, every listed file present, every row readable.
    @MainActor func testBundledSet() throws {
        let set = PuzzleSet.shared
        XCTAssertEqual(set.bands.map(\.band), Array(1...8))
        for b in set.bands {
            var raw = 0
            for f in b.files {
                let d = try Data(contentsOf: set.folder.appending(path: f))
                raw += ((try JSONSerialization.jsonObject(with: d) as? [String: Any])?["puzzles"] as? [Any])?.count ?? 0
            }
            let read = set.band(b.band)
            XCTAssertGreaterThan(read.count, 0, "band \(b.band)")
            XCTAssertEqual(read.count, raw, "band \(b.band): every row parses")
            XCTAssertEqual(Set(read.map(\.id)).count, read.count, "band \(b.band): ids are unique")
        }
    }
}

/// Difficulty and what comes next.
final class PuzzleProgressTests: XCTestCase {
    func testSteps() {
        XCTAssertEqual(PuzzleProgress.bandOf(step: 0), 1)
        XCTAssertEqual(PuzzleProgress.bandOf(step: 1), 1)
        XCTAssertEqual(PuzzleProgress.bandOf(step: 2), 2)
        XCTAssertEqual(PuzzleProgress.bandOf(step: 15), 8)
        XCTAssertEqual(PuzzleProgress.bandOf(step: 99), 8)
        XCTAssertEqual(PuzzleProgress.nextStep(0, .solved), 1)
        XCTAssertEqual(PuzzleProgress.nextStep(15, .solved), 15)
        XCTAssertEqual(PuzzleProgress.nextStep(5, .missed), 4)
        XCTAssertEqual(PuzzleProgress.nextStep(5, .shown), 3)
        XCTAssertEqual(PuzzleProgress.nextStep(1, .shown), 0)
        XCTAssertEqual(PuzzleProgress.bandOrder(3), [3, 4, 2, 5, 1, 6, 7, 8])
        XCTAssertEqual(PuzzleProgress.bandOrder(8), [8, 7, 6, 5, 4, 3, 2, 1])
    }

    /// Clean solves step up a band every two puzzles; a miss steps back.
    func testBandStepping() {
        var p = PuzzleProgress()
        XCTAssertEqual(p.band, 1, "starts in the easiest band")
        p.finish("a", .solved); p.finish("b", .solved)
        XCTAssertEqual(p.band, 2)
        p.finish("c", .missed)
        XCTAssertEqual(p.band, 1)
        XCTAssertEqual(p.done, ["a": 1, "b": 1, "c": 1])
        p.finish("d", .shown)
        XCTAssertEqual(p.done["d"], 0, "shown counts as seen, not solved")
        XCTAssertEqual(p.step, 0)
    }

    private func fake(_ n: Int) -> [Puzzle] {
        (0..<3).map { Puzzle(id: "\(n)-\($0)", fen: "8/8/8/8/8/8/8/K6k w - - 0 1", moves: ["a1a2", "h1h2"], mate: 0, band: n) }
    }

    /// Nothing repeats until every puzzle has been seen; then the unsolved come round first.
    func testNoRepeats() {
        var p = PuzzleProgress()
        var seen: [String] = []
        for i in 0..<24 {
            guard let next = p.next(in: fake) else { return XCTFail("ran out at \(i)") }
            XCTAssertFalse(seen.contains(next.id), "\(next.id) repeated")
            seen.append(next.id)
            if i % 5 == 0 { p.finish(next.id, .shown) } else { p.skip(next.id); p.done[next.id] = 1 }
        }
        XCTAssertEqual(seen.count, 24)
        let again = p.next(in: fake)
        XCTAssertNotNil(again)
        XCTAssertEqual(p.done[again!.id], 0, "the record of what was seen is kept (audit F17)")
        XCTAssertTrue(["0", "5", "10", "15", "20"].map { seen[Int($0)!] }.contains(again!.id), "an unsolved one comes back first")
    }

    func testUsedUpBandFallsToTheNearest() {
        var p = PuzzleProgress(step: 4) // band 3
        for x in fake(3) { p.done[x.id] = 1 }
        XCTAssertEqual(p.next(in: fake)?.band, 4, "the harder neighbor first")
    }

    func testKept() throws {
        let d = UserDefaults(suiteName: "puzzle-tests-\(UUID())")!
        var p = PuzzleProgress(step: 7)
        p.done = ["x": 1]
        p.current = .init(id: "y", band: 4, missed: true)
        p.save(d)
        XCTAssertEqual(PuzzleProgress.load(d), p)
        d.set(Data("junk".utf8), forKey: PuzzleProgress.key)
        XCTAssertEqual(PuzzleProgress.load(d), PuzzleProgress(), "unreadable progress starts over")
    }
}

/// Solving, through core's real rules, with no pauses.
@MainActor
final class PuzzleModelTests: XCTestCase {
    // White plays d4b5; Black wins with c3c2, then White takes the rook (h3a3), then c2c1q.
    let line = Puzzle(id: "Gdz7L", fen: "8/5pk1/4p1p1/3p4/3N4/r1p4R/5PKP/8 w - - 3 44", moves: ["d4b5", "c3c2", "h3a3", "c2c1q"], mate: 0, band: 1)
    // Black plays c7c6; White mates on the back rank with either rook. The line says a1a8.
    let twoMates = Puzzle(id: "mate", fen: "7k/2p3pp/8/8/8/8/1R6/R5K1 b - - 0 1", moves: ["c7c6", "a1a8"], mate: 1, band: 1)
    var defaults: UserDefaults!

    override func setUp() async throws {
        Core.shared.boot()
        defaults = UserDefaults(suiteName: "puzzle-model-\(UUID())")!
    }

    private func model() -> PuzzleModel { PuzzleModel(defaults: defaults, pace: 0) }

    func testOpponentMovesFirstAndTheBoardFacesTheSolver() async {
        let m = model()
        await m.begin(line)
        XCTAssertEqual(m.played, ["d4b5"])
        XCTAssertEqual(m.phase, .solve)
        XCTAssertEqual(m.snap.turn, "b")
        XCTAssertFalse(m.whiteAtBottom, "Black solves, so Black is at the bottom")
        XCTAssertEqual(m.turnLine, "Black to move.")
        XCTAssertEqual(m.expected, "c3c2")
        XCTAssertEqual(m.shownLast, "d4b5", "the opponent's move is marked")
    }

    func testTheLineSolved() async {
        let m = model()
        await m.begin(line)
        await m.attempt("c3c2")
        XCTAssertEqual(m.played, ["d4b5", "c3c2", "h3a3"], "the opponent replies")
        XCTAssertEqual(m.phase, .solve)
        await m.attempt("c2c1q")
        XCTAssertEqual(m.phase, .done)
        XCTAssertEqual(m.result, .solved)
        XCTAssertEqual(m.line, "Solved.")
        XCTAssertEqual(m.progress.step, 1, "a clean solve steps up")
        XCTAssertEqual(m.progress.done["Gdz7L"], 1)
        XCTAssertNil(m.progress.current)
    }

    func testAWrongMoveGoesBack() async {
        let m = model()
        await m.begin(line)
        let before = m.snap.board
        XCTAssertFalse(m.canShow)
        await m.attempt("g7f6")
        XCTAssertEqual(m.phase, .solve, "tried again as often as wanted")
        XCTAssertEqual(m.snap.board, before, "the piece went back")
        XCTAssertEqual(m.played, ["d4b5"])
        XCTAssertEqual(m.line, "Not that one.")
        XCTAssertTrue(m.missed)
        XCTAssertTrue(m.canShow)
        XCTAssertEqual(m.progress.current?.missed, true, "a miss is remembered")
        await m.attempt("g7g8")
        XCTAssertEqual(m.phase, .solve)
        await m.attempt("c3c2")
        await m.attempt("c2c1q")
        XCTAssertEqual(m.result, .missed)
        XCTAssertEqual(m.progress.step, 0, "a miss steps down, never below the start")
    }

    func testShowTheMove() async {
        let m = model()
        await m.begin(line)
        await m.showMove()
        XCTAssertEqual(m.played, ["d4b5"], "only after a miss")
        await m.attempt("g7f6")
        await m.showMove()
        XCTAssertEqual(m.played, ["d4b5", "c3c2", "h3a3", "c2c1q"], "plays out the rest of the line")
        XCTAssertEqual(m.phase, .done)
        XCTAssertEqual(m.result, .shown)
        XCTAssertEqual(m.progress.done["Gdz7L"], 0, "seen, not solved")
    }

    func testAnotherMateCounts() async {
        let m = model()
        await m.begin(twoMates)
        XCTAssertEqual(m.turnLine, "White to move.")
        XCTAssertEqual(m.goalLine, "Mate in one.")
        await m.attempt("b2b8")
        XCTAssertEqual(m.phase, .done)
        XCTAssertEqual(m.result, .solved)
        XCTAssertEqual(m.snap.outcome?.reason, "checkmate")
    }

    func testANonMatingOtherMoveIsWrong() async {
        let m = model()
        await m.begin(twoMates)
        await m.attempt("b2b7")
        XCTAssertEqual(m.result, nil)
        XCTAssertTrue(m.missed)
    }

    func testRetryCountsOnce() async {
        let m = model()
        await m.begin(twoMates)
        await m.attempt("a1a8")
        XCTAssertEqual(m.progress.step, 1)
        await m.retry()
        XCTAssertEqual(m.phase, .solve)
        XCTAssertEqual(m.played, ["c7c6"])
        await m.attempt("a1a8")
        XCTAssertEqual(m.phase, .done)
        XCTAssertEqual(m.progress.step, 1, "solving it again changes nothing")
    }

    func testNextFromTheBundledSetDoesNotRepeat() async {
        let m = model()
        await m.start()
        XCTAssertEqual(m.puzzle?.band, 1, "starts in an easy band")
        var ids: Set<String> = [m.puzzle!.id]
        for _ in 0..<5 {
            await m.next()
            guard let p = m.puzzle else { return XCTFail("no puzzle") }
            XCTAssertFalse(ids.contains(p.id))
            ids.insert(p.id)
            XCTAssertEqual(m.phase, .solve)
        }
        XCTAssertEqual(m.progress.step, 0, "skipping does not move the difficulty")
    }

    func testThePuzzleInHandComesBack() async {
        let first = model()
        await first.start()
        let id = first.puzzle?.id
        let again = model()
        await again.start()
        XCTAssertEqual(again.puzzle?.id, id)
    }
}
