import XCTest
@testable import ZeistChess

final class ClockTests: XCTestCase {
    private let blitz = TimeControl.minutes(3, 2)

    func testTheFirstMoveIsFreeThenTheSideToMoveCountsDown() {
        var c = ChessClock(control: blitz, paused: false, at: 0)
        XCTAssertNil(c.running)
        c.moved("w", at: 5)                       // White's first move: no clock ran, no increment
        XCTAssertEqual(c.remaining("w", at: 5), 180)
        XCTAssertEqual(c.running, "b")
        XCTAssertEqual(c.remaining("b", at: 9), 176, accuracy: 1e-9)
        XCTAssertEqual(c.remaining("w", at: 9), 180)   // only the side to move counts down
    }

    func testIncrementIsAddedAfterEachMove() {
        var c = ChessClock(control: blitz, paused: false, at: 0)
        c.moved("w", at: 0)
        c.moved("b", at: 10)                      // Black spent 10 s, gains 2
        XCTAssertEqual(c.remaining("b", at: 10), 172, accuracy: 1e-9)
        c.moved("w", at: 13)                      // White spent 3 s, gains 2
        XCTAssertEqual(c.remaining("w", at: 13), 179, accuracy: 1e-9)
        XCTAssertEqual(c.running, "b")
    }

    func testFlagFalls() {
        var c = ChessClock(control: .minutes(1), paused: false, at: 0)
        c.moved("w", at: 0)
        XCTAssertNil(c.flagged(at: 59.9))
        XCTAssertEqual(c.untilFlag(at: 59.9)!, 0.1, accuracy: 1e-9)
        XCTAssertEqual(c.flagged(at: 60), "b")
        XCTAssertEqual(c.remaining("b", at: 75), 0)    // never below zero
    }

    func testPauseAndRestore() {
        var c = ChessClock(control: blitz, paused: false, at: 0)
        c.moved("w", at: 0)
        c.pause(at: 30)                           // Black has used 30 s, then the app goes away
        XCTAssertEqual(c.remaining("b", at: 500), 150, accuracy: 1e-9)
        XCTAssertNil(c.flagged(at: 10_000))
        // Saved and read back as a game picked up again later, at a different uptime.
        var back = ChessClock(control: blitz, white: c.remaining("w", at: 0), black: c.remaining("b", at: 0), running: "b", paused: true)
        back.resume(at: 1000)
        XCTAssertEqual(back.remaining("b", at: 1010), 140, accuracy: 1e-9)
        c.resume(at: 900)
        XCTAssertEqual(c.remaining("b", at: 910), 140, accuracy: 1e-9)
        c.stop(at: 920)
        XCTAssertNil(c.running)
        XCTAssertEqual(c.remaining("b", at: 5000), 130, accuracy: 1e-9)
    }

    func testAMoveWhilePausedStillAddsTheIncrement() {
        var c = ChessClock(control: blitz, paused: false, at: 0)
        c.moved("w", at: 0)
        c.pause(at: 4)
        c.moved("b", at: 100)
        XCTAssertEqual(c.remaining("b", at: 100), 178, accuracy: 1e-9)
        XCTAssertEqual(c.remaining("w", at: 200), 180)  // still paused
    }

    func testWords() {
        XCTAssertEqual(ChessClock.say(180), "3:00")
        XCTAssertEqual(ChessClock.say(42.7), "0:42")
        XCTAssertEqual(ChessClock.say(9.46), "0:09.4")
        XCTAssertEqual(ChessClock.say(0), "0:00.0")
        XCTAssertEqual(ChessClock.say(3900), "1:05:00")
        XCTAssertEqual(ChessClock.spoken(178), "2 minutes 58 seconds")
        XCTAssertEqual(ChessClock.spoken(9.9), "9 seconds")
        XCTAssertEqual(ChessClock.pgn(ms: 178_400), "0:02:58.4")
        XCTAssertEqual(ChessClock.pgn(ms: 3_725_000), "1:02:05.0")
    }

    func testTimeControls() {
        XCTAssertEqual(TimeControl.minutes(1).name, "1 min")
        XCTAssertEqual(TimeControl.minutes(3, 2).name, "3+2")
        XCTAssertEqual(TimeControl.minutes(3, 2).pgn, "180+2")
        XCTAssertEqual(TimeControl(pgn: "180+2"), .minutes(3, 2))
        XCTAssertNil(TimeControl(pgn: "nonsense"))
        XCTAssertEqual(TimeControl.minutes(2, 1).kind, .bullet)
        XCTAssertEqual(TimeControl.minutes(3).kind, .blitz)
        XCTAssertEqual(TimeControl.minutes(5, 3).kind, .blitz)
        XCTAssertEqual(TimeControl.minutes(10).kind, .rapid)
        XCTAssertEqual(TimeControl.minutes(15, 10).kind, .rapid)
        XCTAssertEqual(TimeControl.minutes(30, 20).kind, .classical)
        for (kind, controls) in TimeControl.presets { for c in controls { XCTAssertEqual(c.kind, kind, c.name) } }
    }
}

final class MaterialTests: XCTestCase {
    private func board(_ fen: String) -> [String] { Square.board(fromFEN: fen) }

    func testCapturesAndLead() {
        // 1. e4 d5 2. exd5 Qxd5 3. Nc3 Qa5 4. Nf3 ... White has taken a pawn, Black a pawn.
        let b = board("rnb1kbnr/ppp1pppp/8/q7/8/2N2N2/PPPP1PPP/R1BQKB1R b KQkq - 3 4")
        XCTAssertEqual(Material.captured(by: "w", b).map(\.kind), ["P"])
        XCTAssertEqual(Material.captured(by: "b", b).map(\.kind), ["P"])
        XCTAssertEqual(Material.balance(b), 0)
        // Black is missing its e-pawn and a knight; White has everything: +4.
        let c = board("rnbqkb1r/pppp1ppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1")
        XCTAssertEqual(Material.captured(by: "w", c).map { "\($0.count)\($0.kind)" }, ["1P", "1N"])
        XCTAssertTrue(Material.captured(by: "b", c).isEmpty)
        XCTAssertEqual(Material.lead("w", c), 4)
        XCTAssertEqual(Material.lead("b", c), 0)
    }

    func testFifteenCaptured() {
        let b = board("4k3/8/8/8/8/8/PPPPPPPP/RNBQKBNR w KQ - 0 1")
        let taken = Material.captured(by: "w", b)
        XCTAssertEqual(taken.map { "\($0.count)\($0.kind)" }, ["8P", "2N", "2B", "2R", "1Q"])
        XCTAssertEqual(taken.reduce(0) { $0 + $1.count }, 15)
        XCTAssertEqual(Material.lead("w", b), 39)
    }

    func testPromotionCountsAsAPawnGoneNotAPieceTaken() {
        // White promoted a pawn to a second queen; Black has lost only its queen.
        let b = board("rnb1kbnr/pppppppp/8/8/8/8/PPPPPPP1/RNBQKBNQ w - - 0 1")
        XCTAssertEqual(Material.captured(by: "b", b).map { "\($0.count)\($0.kind)" }, ["1R"], "the rook on h1 was taken; the h-pawn became the queen")
        XCTAssertEqual(Material.captured(by: "w", b).map { "\($0.count)\($0.kind)" }, ["1Q"])
        XCTAssertEqual(Material.balance(b), (8 + 9) - 5)  // White: queen from the pawn; Black has its rooks, no queen
        // An under-promotion: a third knight.
        let n = board("4k3/8/8/8/8/8/1PPPPPPP/RNBQKBNN w - - 0 1")
        XCTAssertEqual(Material.lost("w", n).map { "\($0.count)\($0.kind)" }, ["1R"])
    }

    func testCapturesFromASetUpPosition() {
        let start = board("4k3/4p3/8/8/8/8/8/R3K3 w - - 0 1")
        XCTAssertTrue(Material.captured(by: "w", start, from: start).isEmpty)
        let after = board("4k3/8/8/8/8/8/8/4K3 w - - 0 1")
        XCTAssertEqual(Material.captured(by: "w", after, from: start).map { "\($0.count)\($0.kind)" }, ["1P"])
        XCTAssertEqual(Material.captured(by: "b", after, from: start).map { "\($0.count)\($0.kind)" }, ["1R"])
    }

    func testMatingMaterial() {
        XCTAssertFalse(Material.canMate("w", board("4k3/8/8/8/8/8/8/4K3 w - - 0 1")))
        XCTAssertFalse(Material.canMate("w", board("4k3/8/8/8/8/8/8/3NK3 w - - 0 1")))
        XCTAssertFalse(Material.canMate("w", board("4k3/8/8/8/8/8/8/3BK3 w - - 0 1")))
        XCTAssertTrue(Material.canMate("w", board("4k3/8/8/8/8/8/8/2NNK3 w - - 0 1")))
        XCTAssertTrue(Material.canMate("w", board("4k3/8/8/8/8/8/7P/4K3 w - - 0 1")))
        XCTAssertTrue(Material.canMate("b", board("4k2r/8/8/8/8/8/8/4K3 w - - 0 1")))
    }
}

final class PremoveTests: XCTestCase {
    private let start = Square.board(fromFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
    private func names(_ s: Set<Int>) -> Set<String> { Set(s.map(Square.name)) }

    func testTargets() {
        XCTAssertEqual(names(Premove.targets(from: Square.index("e2")!, board: start)), ["e3", "e4", "d3", "f3"])
        XCTAssertEqual(names(Premove.targets(from: Square.index("g1")!, board: start)), ["e2", "f3", "h3"])
        XCTAssertEqual(names(Premove.targets(from: Square.index("e7")!, board: start)), ["e6", "e5", "d6", "f6"])
        // Sliders see through pieces: the position will change before the turn comes.
        XCTAssertTrue(names(Premove.targets(from: Square.index("f1")!, board: start)).isSuperset(of: ["e2", "c4", "a6", "g2", "h3"]))
        XCTAssertEqual(Premove.targets(from: Square.index("d1")!, board: start).count, 21)
        // The king may castle ahead.
        XCTAssertTrue(names(Premove.targets(from: Square.index("e1")!, board: start)).isSuperset(of: ["g1", "c1", "d2", "f2"]))
        XCTAssertTrue(Premove.targets(from: Square.index("e4")!, board: start).isEmpty, "an empty square")
    }

    func testResolvesOnlyWhenLegal() {
        let legal = [
            Snapshot.Legal(uci: "g1f3", from: "g1", to: "f3", san: "Nf3", capture: false, promotion: nil, castle: nil),
            Snapshot.Legal(uci: "e7e8n", from: "e7", to: "e8", san: "e8=N", capture: false, promotion: "n", castle: nil),
            Snapshot.Legal(uci: "e7e8q", from: "e7", to: "e8", san: "e8=Q", capture: false, promotion: "q", castle: nil),
        ]
        XCTAssertEqual(Premove.resolve(from: Square.index("g1")!, to: Square.index("f3")!, legal: legal)?.uci, "g1f3")
        XCTAssertNil(Premove.resolve(from: Square.index("g1")!, to: Square.index("h3")!, legal: legal), "no longer legal: dropped")
        XCTAssertEqual(Premove.resolve(from: Square.index("e7")!, to: Square.index("e8")!, legal: legal)?.uci, "e7e8q", "a premoved promotion is a queen")
    }

    func testSpokenMoves() {
        XCTAssertEqual(Spoken.san("Nxf3+"), "Knight takes f3, check")
        XCTAssertEqual(Spoken.san("e4"), "Pawn to e4")
        XCTAssertEqual(Spoken.san("exd5"), "Pawn from e takes d5")
        XCTAssertEqual(Spoken.san("O-O-O#"), "Castles queenside, checkmate")
        XCTAssertEqual(Spoken.san("e8=Q"), "Pawn to e8, promotes to queen")
        XCTAssertEqual(Spoken.san("Rae1"), "Rook from a to e1")
    }
}

final class TimedLogTests: XCTestCase {
    func testPGNCarriesTheClock() throws {
        var r = GameRecord(startFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", fen: "", player: "w",
                           engineID: "stockfish-lite", engineName: "Stockfish Lite", engineVersion: "19.0.1", packSHA: nil,
                           level: 3, adaptive: true, engineSettings: nil, seed: 7, appVersion: "1.0 (1)")
        r.moves = ["f2f3", "e7e5", "g2g4"]; r.san = ["f3", "e5", "g4"]
        r.timeControl = .minutes(3, 2); r.timeClass = "blitz"
        r.clocks = [180_000, 179_400, 178_250]
        r.result = "0-1"; r.ending = "timeout"
        let pgn = GameLog.pgn(r)
        XCTAssertTrue(pgn.contains("[TimeControl \"180+2\"]"))
        XCTAssertTrue(pgn.contains("[Termination \"time forfeit\"]"))
        XCTAssertTrue(pgn.contains("1. f3 {[%clk 0:03:00.0]} e5 {[%clk 0:02:59.4]} 2. g4 {[%clk 0:02:58.2]} 0-1"), pgn)
        let back = try GameLog.decoder.decode(GameRecord.self, from: GameLog.encoder.encode(r))
        XCTAssertEqual(back.timeControl, .minutes(3, 2))
        XCTAssertEqual(back.clocks, r.clocks)
        XCTAssertEqual(back.timeClass, "blitz")
        r.timeControl = nil; r.clocks = nil; r.ending = "checkmate"
        XCTAssertTrue(GameLog.pgn(r).contains("[TimeControl \"-\"]"))
        XCTAssertFalse(GameLog.pgn(r).contains("%clk"))
    }

    func testAnOlderRecordWithoutClocksStillReads() throws {
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","startedAt":"2026-11-14T10:00:00.000Z","startFEN":"x","fen":"x","moves":[],"san":[],"player":"w","engineID":"e","engineName":"E","engineVersion":"1","level":1,"adaptive":true,"seed":1,"undos":0,"appVersion":"1"}"#
        let r = try GameLog.decoder.decode(GameRecord.self, from: Data(old.utf8))
        XCTAssertNil(r.timeControl)
        XCTAssertNil(r.clocks)
    }

    func testReplayClockAtAPly() {
        var r = GameRecord(startFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", fen: "", player: "w",
                           engineID: "e", engineName: "E", engineVersion: "1", packSHA: nil, level: 1, adaptive: true, engineSettings: nil, seed: 1, appVersion: "1")
        r.timeControl = .minutes(1); r.clocks = [60_000, 58_000, 55_000]
        XCTAssertEqual(ReplayScreen.clock(r, "w", at: 0), 60_000)
        XCTAssertEqual(ReplayScreen.clock(r, "b", at: 1), 60_000)
        XCTAssertEqual(ReplayScreen.clock(r, "b", at: 2), 58_000)
        XCTAssertEqual(ReplayScreen.clock(r, "w", at: 3), 55_000)
    }
}

@MainActor
final class PhaseTwoTests: XCTestCase {
    func testEveryPracticePositionIsPlayable() async throws {
        Core.shared.boot()
        for s in PositionSheet.setups {
            let v = try await Core.shared.call("parse", ["text": s.fen]) as? [String: Any]
            XCTAssertNil(v?["error"], "\(s.name): \(v?["error"] ?? "")")
            XCTAssertEqual(v?["kind"] as? String, "fen", s.name)
            XCTAssertFalse(s.name.lowercased().contains("new"))
        }
    }

    func testTheEngineEvaluationIsRead() {
        XCTAssertEqual(GameModel.evaluation(["lines": [["multipv": 1, "cp": -712, "move": "e2e4"]]]), -712)
        XCTAssertEqual(GameModel.evaluation(["lines": [["multipv": 1, "mate": -3, "move": "e2e4"]]]), -10000)
        XCTAssertEqual(GameModel.evaluation(["lines": [["multipv": 1, "mate": 2, "move": "e2e4"]]]), 10000)
        XCTAssertNil(GameModel.evaluation(["lines": [] as [Any]]))
        XCTAssertNil(GameModel.evaluation(["move": "e2e4"]))
    }

    func testFromPositionAndOpeningInTheLog() throws {
        var r = GameRecord(startFEN: "8/8/8/4k3/8/8/8/R3K3 w - - 0 1", fen: "", player: "w", engineID: "e", engineName: "E", engineVersion: "1",
                           packSHA: nil, level: 1, adaptive: true, engineSettings: nil, seed: 1, appVersion: "1")
        XCTAssertTrue(r.fromPosition)
        r.startFEN = GameModel.standardStart
        XCTAssertFalse(r.fromPosition)
        r.openingECO = "B20"; r.openingName = "Sicilian Defense"; r.hints = 2; r.ending = "agreement"; r.result = "1/2-1/2"
        let pgn = GameLog.pgn(r)
        XCTAssertTrue(pgn.contains("[ECO \"B20\"]"))
        XCTAssertTrue(pgn.contains("[Opening \"Sicilian Defense\"]"))
        XCTAssertTrue(pgn.contains("[Termination \"agreement\"]"))
        let back = try GameLog.decoder.decode(GameRecord.self, from: GameLog.encoder.encode(r))
        XCTAssertEqual(back.hints, 2)
        XCTAssertEqual(back.openingName, "Sicilian Defense")
        XCTAssertEqual(GameRow.word(back), "Draw agreed")
    }

    func testOpeningsAndPositionsThroughCore() async throws {
        Core.shared.boot()
        let o = try await Core.shared.call("opening", ["moves": ["e2e4", "c7c5"]]) as? [String: Any]
        XCTAssertEqual(o?["name"] as? String, "Sicilian Defense")
        let p = try await Core.shared.call("parse", ["text": "1. e4 e5 2. Nf3 Nc6 3. Bb5 a6"]) as? [String: Any]
        XCTAssertEqual((p?["fens"] as? [String])?.count, 7)
        let bad = try await Core.shared.call("parse", ["text": "not a game"]) as? [String: Any]
        XCTAssertNotNil(bad?["error"] as? String)
    }
}
