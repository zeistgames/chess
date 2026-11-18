import XCTest
@testable import ZeistChess

/// The defects found by the audit of 2026-11-16 (Zeist's docs/reviews/2026-11-16-codex-audit.md), each reproduced
/// here before it was fixed, and kept so it stays fixed.

/// A door an async step waits at until the test opens it.
@MainActor final class Gate {
    private(set) var waiting = false
    private var door: CheckedContinuation<Void, Never>?
    func wait() async { waiting = true; await withCheckedContinuation { door = $0 } }
    func open() { door?.resume(); door = nil }
    func arrived() async { while !waiting { await Task.yield() } }
}

// MARK: F03: an old account answer never overwrites or clears a newer login

@MainActor
final class AccountRaceTests: XCTestCase {
    private func answer(_ owner: String?) -> Data {
        owner.map { Data(#"{"user":{"handle":"h-\#($0)","owner":"\#($0)"}}"#.utf8) } ?? Data(#"{"user":null}"#.utf8)
    }

    private func race(_ old: String?) async -> (token: String?, owner: String?) {
        let a = Account.shared
        let saved = a.fetch
        defer { a.fetch = saved }
        Keychain.token = "token-A"
        let gate = Gate()
        let body = answer(old)
        a.fetch = { req in
            await gate.wait()
            return (body, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let t = Task { await a.refresh() }
        await gate.arrived()
        Keychain.token = "token-B" // a newer sign-in lands while A's answer is on its way
        gate.open()
        await t.value
        let out = (Keychain.token, a.owner)
        Keychain.token = nil
        return out
    }

    func testAnOldAnswerDoesNotRestoreTheOldAccount() async {
        let r = await race("owner-A")
        XCTAssertEqual(r.token, "token-B")
        XCTAssertNotEqual(r.owner, "owner-A", "A's answer was for a session no longer installed")
    }

    func testAnOldSignedOutAnswerDoesNotClearTheNewSession() async {
        let r = await race(nil)
        XCTAssertEqual(r.token, "token-B", "B's valid session stays")
    }
}

extension AccountRaceTests {
    /// Review of F03: a sign-out that answers after a newer sign-in forgets only the session it was for.
    func testALateSignOutDoesNotForgetTheNewSession() async {
        let a = Account.shared
        let saved = a.fetch
        defer { a.fetch = saved; Keychain.token = nil }
        Keychain.token = "token-A"
        let gate = Gate()
        a.fetch = { req in
            await gate.wait()
            return (Data(), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let t = Task { await a.signOut() }
        await gate.arrived()
        Keychain.token = "token-B"
        gate.open()
        await t.value
        XCTAssertEqual(Keychain.token, "token-B", "B signed in while A's sign-out was on its way")
    }
}

// MARK: F10: a game keeps the owner it was started under

@MainActor
final class GameOwnerTests: XCTestCase {
    private func record() -> GameRecord {
        GameRecord(startFEN: GameModel.standardStart, fen: GameModel.standardStart, player: "w", engineID: "test", engineName: "Test",
                   engineVersion: "1", packSHA: nil, level: 1, adaptive: false, rating: nil, engineSettings: nil, seed: 1, appVersion: "test")
    }
    private func stored(_ id: UUID) -> GameRecord? { GameLog.shared.all.first { $0.id == id } }
    private func cleanUp(_ ids: [UUID]) {
        for id in ids { try? FileManager.default.removeItem(at: GameLog.folder.appending(path: "\(id.uuidString).json")) }
        GameLog.shared.load()
    }

    func testAnAccountsGameIsNeverPassedToAnother() {
        let log = GameLog.shared
        let r = record()
        defer { cleanUp([r.id]) }
        log.save(r, owner: "owner-A", handle: "a")              // started signed in as A
        log.save(r, owner: nil, handle: nil)                     // A's session ended; the open board saves its copy
        XCTAssertEqual(stored(r.id)?.account, "owner-A", "A's game stays A's")
        log.stamp(owner: "owner-B", handle: "b")                 // B signs in
        XCTAssertEqual(stored(r.id)?.account, "owner-A", "and never becomes B's")
    }

    func testAGuestGameIsClaimedOnce() {
        let log = GameLog.shared
        let r = record()
        defer { cleanUp([r.id]) }
        log.save(r, owner: nil, handle: nil)
        log.stamp(owner: "owner-B", handle: "b")
        XCTAssertEqual(stored(r.id)?.account, "owner-B", "the first account to sign in claims a guest game")
        log.save(r, owner: nil, handle: nil)
        log.stamp(owner: "owner-C", handle: "c")
        XCTAssertEqual(stored(r.id)?.account, "owner-B", "once")
    }
}

extension GameOwnerTests {
    /// Review of F10: on a shared phone, Games shows only the games of whoever is signed in; signed out, only guest
    /// games. Another account's games stay stored and come back when it signs in.
    func testGamesShowsOnlyTheViewersGames() {
        let log = GameLog.shared
        let saved = log.viewer
        let a = record(), g = record()
        defer { log.viewer = saved; cleanUp([a.id, g.id]) }
        log.save(a, owner: "owner-A", handle: "a")
        log.save(g, owner: nil, handle: nil)
        log.viewer = { "owner-B" }
        XCTAssertFalse(log.games.contains { $0.id == a.id }, "B does not see A's game")
        XCTAssertFalse(log.games.contains { $0.id == g.id }, "nor a guest game B has not claimed")
        XCTAssertNotEqual(log.current?.id, a.id, "nor can B continue A's game")
        XCTAssertFalse(log.countsHere(stored(a.id)!), "nor does A's game count for B anywhere (Game Center, Measure, sharing)")
        log.viewer = { nil }
        XCTAssertFalse(log.games.contains { $0.id == a.id }, "a guest does not see A's game")
        XCTAssertTrue(log.games.contains { $0.id == g.id }, "a guest sees guest games")
        log.viewer = { "owner-A" }
        XCTAssertTrue(log.games.contains { $0.id == a.id }, "A's game comes back for A")
        XCTAssertTrue(log.countsHere(stored(a.id)!))
    }
}

// MARK: F15: a late answer never lands on a board that has moved on

@MainActor
final class StaleAnswerTests: XCTestCase {
    override func setUp() async throws { Core.shared.boot() }

    func testAPuzzleReplyAfterNextIsDropped() async {
        let line = Puzzle(id: "Gdz7L", fen: "8/5pk1/4p1p1/3p4/3N4/r1p4R/5PKP/8 w - - 3 44", moves: ["d4b5", "c3c2", "h3a3", "c2c1q"], mate: 0, band: 1)
        let other = Puzzle(id: "mate", fen: "7k/2p3pp/8/8/8/8/1R6/R5K1 b - - 0 1", moves: ["c7c6", "a1a8"], mate: 1, band: 1)
        let gate = Gate()
        var held = false
        let m = PuzzleModel(defaults: UserDefaults(suiteName: "stale-\(UUID())")!, rules: { fen, moves in
            if fen == line.fen, moves.count == 3, !held { held = true; await gate.wait() }
            return try await PuzzleModel.coreRules(fen, moves)
        }, pace: 0)
        await m.begin(line)
        let t = Task { await m.attempt("c3c2") }       // right: the opponent's reply is on its way
        await gate.arrived()
        await m.begin(other)                            // Next, while the reply is still out
        gate.open()
        await t.value
        XCTAssertEqual(m.puzzle?.id, "mate")
        XCTAssertEqual(m.played, ["c7c6"], "the old reply did not land on the new puzzle")
    }

    func testALessonReplyAfterBackIsDropped() async throws {
        let lib = LessonLibrary(folder: LessonFixtures.folder)
        let lesson = try XCTUnwrap(lib.lesson("checkmates-scholars-mate"))
        let gate = Gate()
        var held = false
        let m = LessonModel(lesson: lesson, store: LearnStore(defaults: UserDefaults(suiteName: "stale-\(UUID())")!), rules: { fen, moves in
            if moves == ["f1c4", "b8c6"], !held { held = true; await gate.wait() }
            return try await PuzzleModel.coreRules(fen, moves)
        }, pace: 0)
        m.voiceOver = { true }
        await m.start(at: 1)
        let t = Task { await m.attempt("f1c4") }       // right: the reply is on its way
        await gate.arrived()
        await m.back()                                  // Back, while the reply is still out
        gate.open()
        await t.value
        XCTAssertEqual(m.index, 0)
        XCTAssertEqual(m.played, [], "the old reply did not land on the step gone back to")
        XCTAssertEqual(m.snap.fen, lesson.steps[0].fen)
    }
}

extension StaleAnswerTests {
    /// The same defect when a step opens: its position arrives after another step has opened.
    func testAStepsLatePositionDoesNotReplaceTheStepOpenedSince() async throws {
        let lib = LessonLibrary(folder: LessonFixtures.folder)
        let lesson = try XCTUnwrap(lib.lesson("checkmates-scholars-mate"))
        let gate = Gate()
        var held = false
        let late = try XCTUnwrap(lesson.steps[4].fen)
        let m = LessonModel(lesson: lesson, store: LearnStore(defaults: UserDefaults(suiteName: "stale-\(UUID())")!), rules: { fen, moves in
            if fen == late, moves.isEmpty, !held { held = true; await gate.wait() }
            return try await PuzzleModel.coreRules(fen, moves)
        }, pace: 0)
        m.voiceOver = { true }
        await m.start(at: 0)
        let t = Task { await m.open(4) }               // its position is slow to come
        await gate.arrived()
        await m.open(0)                                 // another step opens meanwhile
        gate.open()
        await t.value
        XCTAssertEqual(m.index, 0)
        XCTAssertEqual(m.snap.fen, lesson.steps[0].fen, "the late position did not replace it")
    }
}

// MARK: F17 is in PuzzleReplayRuleTests.swift: Zeist's rule for the record and playing the set again.

// MARK: F18: once a side's time has run out, a move does not bring it back

final class ClockFlagTests: XCTestCase {
    func testAMoveAfterTheFlagLeavesTheFlag() {
        var c = ChessClock(control: TimeControl(base: 60, increment: 2), white: 0.01, black: 60, running: "w", paused: false, at: 0)
        XCTAssertEqual(c.flagged(at: 0.011), "w")
        c.moved("w", at: 0.011)
        XCTAssertEqual(c.flagged(at: 0.011), "w", "no increment, no switch: White's time is up")
        XCTAssertEqual(c.remaining("w", at: 0.011), 0)    }

    func testAPausedClockWithNoTimeLeftGivesNoIncrement() {
        var c = ChessClock(control: TimeControl(base: 60, increment: 2), white: 0, black: 60, running: "w", paused: true, at: 0)
        c.moved("w", at: 5)
        XCTAssertEqual(c.remaining("w", at: 5), 0)
        XCTAssertEqual(c.running, "w")
    }
}

// MARK: F19: a lone minor piece can win on time when the other side has something to be mated with

final class FlagMaterialTests: XCTestCase {
    func testALoneBishopCanMateAgainstPawns() {
        let b = Square.board(fromFEN: "k7/p1KB3p/8/8/8/8/8/8 b - - 0 1")
        XCTAssertTrue(Material.canMate("w", b), "h7h6 d7c6 is mate: a Black flag here is a White win")
    }

    func testTheDrawnCases() {
        XCTAssertFalse(Material.canMate("w", Square.board(fromFEN: "k7/8/2K5/8/8/8/8/8 b - - 0 1")), "a bare king")
        XCTAssertFalse(Material.canMate("w", Square.board(fromFEN: "k7/8/2KB4/8/8/8/8/8 b - - 0 1")), "king and bishop against a bare king")
        XCTAssertFalse(Material.canMate("w", Square.board(fromFEN: "k7/8/2KN4/8/8/8/8/8 b - - 0 1")), "king and knight against a bare king")
        XCTAssertTrue(Material.canMate("w", Square.board(fromFEN: "kn6/8/2KN4/8/8/8/8/8 b - - 0 1")), "a knight against a knight can mate")
        XCTAssertTrue(Material.canMate("w", Square.board(fromFEN: "k7/8/2KR4/8/8/8/8/8 b - - 0 1")))
    }
}

extension FlagMaterialTests {
    /// Review of the F19 fix: bishops that all stand on one color can never mate, whatever their number.
    func testBishopsAllOnOneColorCannotMate() {
        XCTAssertFalse(Material.canMate("w", Square.board(fromFEN: "k7/8/2K5/8/8/8/1B6/B7 b - - 0 1")), "two bishops on dark squares against a bare king")
        XCTAssertFalse(Material.canMate("w", Square.board(fromFEN: "kb6/8/2K5/8/8/8/8/B7 b - - 0 1")), "king and bishop against king and bishop, same color")
        XCTAssertTrue(Material.canMate("w", Square.board(fromFEN: "k7/8/2K5/8/8/8/B7/B7 b - - 0 1")), "two bishops on opposite colors")
        XCTAssertTrue(Material.canMate("w", Square.board(fromFEN: "k1b5/8/2K5/8/8/8/8/B7 b - - 0 1")), "bishops of opposite colors, one each")
        XCTAssertTrue(Material.canMate("w", Square.board(fromFEN: "kn6/8/2K5/8/8/8/1B6/B7 b - - 0 1")), "a knight to block with")
    }
}

// MARK: F20: an engine that runs out of time before the first move does not leave the game stuck

@MainActor
final class FirstMoveTimeoutTests: XCTestCase {
    func testTheGameOffersAWayOn() async throws {
        Core.shared.boot()
        let e = try XCTUnwrap(Shelf.shared.engine(Shelf.bundledID))
        let m = try await GameModel.begin(engine: e, player: "b", level: 1, adaptive: false, time: TimeControl(base: 60, increment: 0))
        defer { GameLog.shared.abandon(m.record.id) }
        m.think = { _ in throw CoreError.outOfTime }
        await m.resume()
        for _ in 0..<100 where m.thinking { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(m.thinking)
        XCTAssertTrue(m.trouble != nil || m.over, "a message with Try again, or the game over: never a board nobody can move on")
    }
}

// MARK: F21 and F28: Learn as you play's cards, after Undo and across a relaunch

@MainActor
final class GameCardsAuditTests: XCTestCase {
    private func card(_ kind: String, ply: Int, shows: Int) -> PlayCard {
        PlayCard(key: kind, kind: kind, side: "player", ply: ply, shows: shows, title: "T", line: "L.", name: nil)
    }

    func testUndoBeforeTheProofTakesTheCardBack() async {
        // The audit's game: a fork at move 9, proved by the capture and answer through move 12.
        let fork = card("fork", ply: 9, shows: 12)
        let fake: ([String], String, String, Bool, Bool) async -> [PlayCard] = { moves, _, _, _, _ in moves.count >= 12 ? [fork] : [] }
        let g = GameCards(gameID: UUID(), defaults: UserDefaults(suiteName: "cards-\(UUID())")!)
        await g.update(moves: Array(repeating: "m", count: 12), player: "w", fen: "", learn: true, over: false, cards: fake)
        XCTAssertEqual(g.current?.key, "fork")
        await g.update(moves: Array(repeating: "m", count: 10), player: "w", fen: "", learn: true, over: false, cards: fake)
        XCTAssertNil(g.current, "the moves that proved it were taken back")
        await g.update(moves: Array(repeating: "m", count: 12), player: "w", fen: "", learn: true, over: false, cards: fake)
        XCTAssertEqual(g.current?.key, "fork", "and it can come again when it happens again")
    }

    func testACardNeverShownIsNotLostOnRelaunch() async {
        let d = UserDefaults(suiteName: "cards-\(UUID())")!
        let id = UUID()
        let both = [card("castling", ply: 3, shows: 3), card("en-passant", ply: 4, shows: 4)]
        let fake: ([String], String, String, Bool, Bool) async -> [PlayCard] = { _, _, _, _, _ in both }
        let g = GameCards(gameID: id, defaults: d)
        await g.update(moves: Array(repeating: "m", count: 5), player: "w", fen: "", learn: true, over: false, cards: fake)
        XCTAssertEqual(g.current?.key, "castling")
        XCTAssertEqual(g.waiting.map(\.key), ["en-passant"])
        // The app is closed with the second card still waiting.
        let again = GameCards(gameID: id, defaults: d)
        await again.update(moves: Array(repeating: "m", count: 5), player: "w", fen: "", learn: true, over: false, cards: fake)
        XCTAssertEqual(again.current?.key, "en-passant", "the card never shown comes after all")
    }
}

// MARK: F29: Show the move then Retry still records a solved daily as solved

@MainActor
final class DailyRetryTests: XCTestCase {
    func testShowThenRetryThenSolveMarksThePuzzleSolved() async throws {
        Core.shared.boot()
        let d = UserDefaults(suiteName: "daily-retry-\(UUID())")!
        let p = try XCTUnwrap(PuzzleSet.shared.daily?.puzzle(2))
        let m = PuzzleModel(source: .daily(day: 2, puzzle: p, start: "2026-11-16"), defaults: d, pace: 0)
        await m.start()
        if let e = m.expected, let wrong = m.snap.legal.first(where: { $0.uci != e }) { await m.attempt(wrong.uci) }
        await m.showMove()
        XCTAssertEqual(PuzzleProgress.load(d).done[p.id], 0, "shown: seen")
        await m.retry()
        var n = 0
        while m.phase == .solve, let e = m.expected, n < 10 { await m.attempt(e); n += 1 }
        let r = PuzzleProgress.load(d)
        XCTAssertNotNil(r.daily?["2"], "the day is recorded")
        XCTAssertEqual(r.done[p.id], 1, "and the puzzle is solved, not only seen")
    }
}

// MARK: Deleting the account

extension AccountRaceTests {
    private func answer(_ req: URLRequest, _ status: Int, _ body: String) -> (Data, URLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    func testDeletingAsksZeistWithTheSessionAndSignsOut() async {
        let a = Account.shared
        let saved = a.fetch
        defer { a.fetch = saved; Keychain.token = nil }
        Keychain.token = "token-A"
        var seen: URLRequest?
        a.fetch = { req in seen = req; return self.answer(req, 200, #"{"ok":true}"#) }
        let done = await a.delete()
        XCTAssertTrue(done)
        XCTAssertEqual(seen?.httpMethod, "DELETE")
        XCTAssertEqual(seen?.url?.path, "/api/me")
        XCTAssertEqual(seen?.value(forHTTPHeaderField: "Authorization"), "Bearer token-A")
        XCTAssertNil(Keychain.token)
        XCTAssertFalse(a.signedIn)
    }

    func testAFailedDeleteChangesNothing() async {
        let a = Account.shared
        let saved = a.fetch
        defer { a.fetch = saved; Keychain.token = nil }
        Keychain.token = "token-A"
        a.fetch = { req in self.answer(req, 500, "") }
        let failed = await a.delete()
        XCTAssertFalse(failed)
        XCTAssertEqual(Keychain.token, "token-A")
        // Refused, and Zeist still knows the session when asked.
        a.fetch = { req in req.httpMethod == "DELETE" ? self.answer(req, 200, #"{"error":"no"}"#) : self.answer(req, 200, #"{"user":{"handle":"a","owner":"owner-a"}}"#) }
        let refused = await a.delete()
        XCTAssertFalse(refused)
        XCTAssertEqual(Keychain.token, "token-A")
    }

    func testALostAnswerStillCountsWhenZeistNoLongerKnowsTheSession() async {
        let a = Account.shared
        let saved = a.fetch
        defer { a.fetch = saved; Keychain.token = nil }
        Keychain.token = "token-A"
        a.fetch = { req in
            if req.httpMethod == "DELETE" { throw URLError(.timedOut) }
            return self.answer(req, 200, #"{"user":null}"#)
        }
        let done = await a.delete()
        XCTAssertTrue(done)
        XCTAssertNil(Keychain.token)
    }

    func testADeletedAccountsGamesStayAsAGuests() {
        let log = GameLog.shared
        var g = GameRecord(startFEN: GameModel.standardStart, fen: GameModel.standardStart, player: "w", engineID: "test", engineName: "Test",
                           engineVersion: "1", packSHA: nil, level: 1, adaptive: false, rating: nil, engineSettings: nil, seed: 1, appVersion: "test")
        defer { try? FileManager.default.removeItem(at: GameLog.folder.appending(path: "\(g.id.uuidString).json")); log.load() }
        log.save(g, owner: "owner-gone", handle: "gone")
        g = log.all.first { $0.id == g.id }!
        XCTAssertEqual(g.account, "owner-gone")
        log.release(owner: "owner-gone")
        XCTAssertNil(log.all.first { $0.id == g.id }?.account)
        log.load()
        XCTAssertNil(log.all.first { $0.id == g.id }?.account, "kept on disk as a guest's")
    }

    func testDeletingWithNoSessionAsksNothing() async {
        let a = Account.shared
        let saved = a.fetch
        defer { a.fetch = saved }
        Keychain.token = nil
        var asked = false
        a.fetch = { req in asked = true; return self.answer(req, 200, #"{"ok":true}"#) }
        let done = await a.delete()
        XCTAssertFalse(done)
        XCTAssertFalse(asked)
    }
}
