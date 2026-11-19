import XCTest
@testable import ZeistChess

/// Zeist's rule for the record and playing the set again (Zeist's docs/PUZZLE-PROGRESS.md, "The record and playing
/// the set again", and nextInSet and replayFinish in its public/s/chess/puzzle.js), case by case. Audit F17.
@MainActor
final class PuzzleReplayRuleTests: XCTestCase {
    private func band(_ n: Int, _ k: Int = 3) -> [Puzzle] {
        (0..<k).map { Puzzle(id: "\(n)-\($0)", fen: "8/8/8/8/8/8/8/K6k w - - 0 1", moves: ["a1a2", "h1h2"], mate: 0, band: n) }
    }
    /// Bands 1 and 2 in hand, the rest read and empty.
    private func two(_ n: Int) -> [Puzzle]? { n <= 2 ? band(n) : [] }

    func testDoneIsNeverClearedAndAnUnfinishedPuzzleComesFirst() {
        var p = PuzzleProgress()
        p.done = ["1-0": 1, "1-1": 0]
        XCTAssertEqual(p.next(in: two)?.id, "1-2")
        XCTAssertEqual(p.done, ["1-0": 1, "1-1": 0])
        XCTAssertNil(p.again)
    }

    func testAFileNotInHandIsNotKnownNeverUsedUp() {
        var p = PuzzleProgress()
        for x in band(1) + band(2) { p.done[x.id] = 1 }
        p.again = ["1-0": 1]
        let before = p
        // Band 3 could not be read: it may hold unfinished puzzles, so nothing is offered and nothing changes.
        XCTAssertNil(p.next(in: { $0 <= 2 ? self.band($0) : $0 == 3 ? nil : [] }))
        XCTAssertEqual(p, before)
    }

    func testTheSetPlaysAgainOnlyWhenEverythingIsDoneSeenFirst() {
        var p = PuzzleProgress()
        for x in band(1) + band(2) { p.done[x.id] = 1 }
        p.done["2-1"] = 0
        XCTAssertEqual(p.next(in: two)?.id, "2-1", "seen and not solved first, though its band is further")
        XCTAssertNil(p.again, "taking a puzzle up marks nothing")
        p.replayFinish("2-1", .shown, moves: "")
        XCTAssertEqual(p.next(in: two)?.id, "1-0", "then all, in the step's order")
    }

    func testARoundEndsAndBeginsAgain() {
        var p = PuzzleProgress()
        for x in band(1) + band(2) { p.done[x.id] = 1 }
        for x in band(1) + band(2) { p.again = (p.again ?? [:]).merging([x.id: 1]) { a, _ in a } }
        XCTAssertEqual(p.next(in: two)?.id, "1-0", "every puzzle in again: it empties and a round begins")
        XCTAssertEqual(p.again ?? [:], [:])
        XCTAssertEqual(p.done.count, 6)
    }

    func testAReplayCountsOnce() {
        var p = PuzzleProgress(step: 5)
        p.done = ["1-0": 0, "1-1": 1]
        p.current = .init(id: "1-0", band: 1)
        XCTAssertTrue(p.replayFinish("1-0", .missed, moves: "a1a2"))
        XCTAssertEqual(p.step, 5, "the step stays")
        XCTAssertEqual(p.done["1-0"], 1, "seen, now solved")
        XCTAssertEqual(p.out?.solved?["1-0"], "a1a2", "and queued to send")
        XCTAssertNil(p.current, "no longer in hand")
        XCTAssertEqual(p.again, ["1-0": 1])
        let before = p.out
        XCTAssertFalse(p.replayFinish("1-1", .solved, moves: "a1a2"), "a solve of one already solved changes nothing")
        XCTAssertFalse(p.replayFinish("1-2", .shown, moves: ""), "nor does Show the move")
        XCTAssertEqual(p.out, before)
        XCTAssertEqual(p.step, 5)
        XCTAssertEqual(p.done["1-1"], 1)
        XCTAssertNil(p.done["1-2"])
        XCTAssertEqual(p.again, ["1-0": 1, "1-1": 1, "1-2": 1])
    }

    func testAnOldBuildsReplayedSetIsReadOnceAsAgain() throws {
        let d = UserDefaults(suiteName: "replay-\(UUID())")!
        d.set(Data(#"{"step":3,"done":{"1-0":1},"replayed":["1-0"]}"#.utf8), forKey: PuzzleProgress.key)
        var p = PuzzleProgress.load(d)
        XCTAssertEqual(p.again, ["1-0": 1])
        p.save(d)
        let raw = try XCTUnwrap(String(data: try XCTUnwrap(d.data(forKey: PuzzleProgress.key)), encoding: .utf8))
        XCTAssertFalse(raw.contains("replayed"), raw)
    }
}

/// The same rule where a puzzle is played: a replayed solve never counts again, for the step, Game Center or Measure,
/// in the run of all puzzles, in a theme and as a day's puzzle.
@MainActor
final class PuzzleReplayModelTests: XCTestCase {
    override func setUp() async throws { Core.shared.boot() }

    private func solve(_ m: PuzzleModel) async {
        var n = 0
        while m.phase == .solve, let e = m.expected, n < 12 { await m.attempt(e); n += 1 }
    }

    private func replay(_ source: PuzzleModel.Source, _ p: Puzzle, round: Bool) async throws {
        let d = UserDefaults(suiteName: "replay-model-\(UUID())")!
        var start = PuzzleProgress(step: 7)
        start.done[p.id] = 0
        start.save(d)
        var reports = 0
        let m = PuzzleModel(source: source, defaults: d, pace: 0)
        m.report = { _, _ in reports += 1 }
        await m.begin(p)
        await solve(m)
        XCTAssertEqual(m.phase, .done)
        let after = PuzzleProgress.load(d)
        XCTAssertEqual(after.step, 7, "the step stays")
        XCTAssertEqual(after.done[p.id], 1, "seen, now solved")
        XCTAssertNotNil(after.out?.solved?[p.id], "queued to send")
        XCTAssertEqual(reports, 0, "not counted again for Game Center or Measure")
        XCTAssertEqual(after.again?[p.id] != nil, round, "only the run of all puzzles marks a round")
    }

    func testInTheRunOfAllPuzzles() async throws {
        try await replay(.all, XCTUnwrap(PuzzleSet.shared.band(2).first), round: true)
    }

    func testInATheme() async throws {
        let t = try XCTUnwrap(PuzzleSet.shared.themes.first)
        let p = try XCTUnwrap((1...8).lazy.compactMap { PuzzleSet.shared.puzzles(of: t, band: $0).first }.first)
        try await replay(.theme(t), p, round: false)
    }

    func testAsADaysPuzzle() async throws {
        let p = try XCTUnwrap(PuzzleSet.shared.daily?.puzzle(2))
        try await replay(.daily(day: 2, puzzle: p, start: "2026-11-16"), p, round: false)
    }

    func testAFirstSolveStillCounts() async throws {
        let p = try XCTUnwrap(PuzzleSet.shared.band(2).first)
        let d = UserDefaults(suiteName: "replay-model-\(UUID())")!
        PuzzleProgress(step: 7).save(d)
        var reports = 0
        let m = PuzzleModel(defaults: d, pace: 0)
        m.report = { _, _ in reports += 1 }
        await m.begin(p)
        await solve(m)
        XCTAssertEqual(reports, 1)
        XCTAssertNotEqual(PuzzleProgress.load(d).step, 7)
    }
}
