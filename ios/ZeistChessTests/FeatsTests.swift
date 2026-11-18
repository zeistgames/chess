import XCTest
@testable import ZeistChess

@MainActor
final class FeatsTests: XCTestCase {
    private func game(_ engine: String = "clover", player: String = "w", result: String = "1-0", moves: [String] = ["e2e4", "e7e5"]) -> GameRecord {
        var g = GameRecord(startFEN: GameModel.standardStart, fen: GameModel.standardStart, player: player, engineID: engine, engineName: engine,
                           engineVersion: "1", packSHA: nil, level: 4, adaptive: true, rating: nil, engineSettings: nil, seed: 1, appVersion: "1.0")
        g.moves = moves
        g.result = result
        g.ending = "checkmate"
        return g
    }

    func testAWinEarnsTheEngineAndALossNothing() {
        XCTAssertEqual(Feats.earned(by: game(), strongest: false), ["zeistchess.first.clover"])
        XCTAssertEqual(Feats.earned(by: game(result: "0-1"), strongest: true), [])
        XCTAssertEqual(Feats.earned(by: game(), strongest: true), ["zeistchess.first.clover", "zeistchess.best.clover", "zeistchess.feat.nohelp"])
        var helped = game(); helped.hints = 1
        XCTAssertFalse(Feats.earned(by: helped, strongest: true).contains("zeistchess.feat.nohelp"))
    }

    func testBlackClocksAndPromotions() {
        var g = game(player: "b", result: "0-1", moves: ["a2a3", "h7h5", "a3a4", "h2h1n", "b7b8q"])
        g.timeClass = "blitz"
        let e = Feats.earned(by: g, strongest: false)
        XCTAssertTrue(e.isSuperset(of: ["zeistchess.feat.black", "zeistchess.feat.blitz", "zeistchess.feat.lesser"]))
        XCTAssertFalse(e.contains("zeistchess.feat.queen"), "the engine's promotion is not the player's")
    }

    func testMaiaByRating() {
        var g = game("maia"); g.rating = 1500
        let e = Feats.earned(by: g, strongest: false)
        XCTAssertTrue(e.isSuperset(of: ["zeistchess.maia.800", "zeistchess.maia.1500"]))
        XCTAssertFalse(e.contains("zeistchess.maia.1800"))
    }

    func testAChosenPositionEarnsOnlyThePracticeEnding() {
        var g = game(); g.startFEN = "8/8/8/4k3/8/8/8/3QK3 w - - 0 1"
        XCTAssertEqual(Feats.earned(by: g, strongest: true), ["zeistchess.feat.ending"])
        g.startFEN = "8/8/8/4k3/8/8/8/QQQQK3 w - - 0 1"
        XCTAssertEqual(Feats.earned(by: g, strongest: true), [])
    }

    func testTheZeistEngineHasNoneOfItsOwn() {
        XCTAssertEqual(Feats.earned(by: game("zeist"), strongest: true), ["zeistchess.feat.nohelp"])
    }

    func testShelfAndPuzzles() {
        XCTAssertEqual(Feats.shelf(met: Set(Feats.engines), beaten: ["zeist"]), ["zeistchess.shelf.met"])
        XCTAssertEqual(Feats.puzzles(solved: 50, hardFirstTry: false), ["zeistchess.puzzles.10", "zeistchess.puzzles.50"])
        XCTAssertTrue(Feats.puzzles(solved: 1, hardFirstTry: true).contains("zeistchess.puzzles.hard"))
    }

    func testEveryIdIsInTheList() throws {
        // The list beside the app (ios/GameCenter/achievements.json) and the code name the same achievements.
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "GameCenter/achievements.json")
        let data = try Data(contentsOf: url)
        let list = try XCTUnwrap((JSONSerialization.jsonObject(with: data) as? [String: Any])?["achievements"] as? [[String: Any]])
        let ids = Set(list.compactMap { $0["id"] as? String })
        var code: Set<String> = ["zeistchess.shelf.met", "zeistchess.shelf.beaten", "zeistchess.puzzles.hard"]
        for e in Feats.engines.filter({ $0 != "zeist" }).map({ $0.replacingOccurrences(of: "-", with: "_") }) { code.insert("zeistchess.first.\(e)"); code.insert("zeistchess.best.\(e)") }
        for r in Feats.maia { code.insert("zeistchess.maia.\(r)") }
        for n in Feats.puzzleCounts { code.insert("zeistchess.puzzles.\(n)") }
        for f in ["black", "bullet", "blitz", "rapid", "queen", "lesser", "ending", "nohelp"] { code.insert("zeistchess.feat.\(f)") }
        XCTAssertEqual(ids, code)
    }
}
