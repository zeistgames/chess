import XCTest
@testable import ZeistChess

@MainActor
final class EngineGamesTests: XCTestCase {
    private func game(engine: String = "zeist", ending: String? = "checkmate", result: String? = "1-0", level: String = "3", seed: String? = "77") -> GameRecord {
        var options: [JSONValue] = [.array([.string("Level"), .string(level)])]
        if let seed { options.append(.array([.string("Seed"), .string(seed)])) }
        var g = GameRecord(startFEN: GameModel.standardStart, fen: GameModel.standardStart, player: "w", engineID: engine, engineName: "Zeist",
                           engineVersion: "1.0", packSHA: nil, level: 4, adaptive: true, rating: nil,
                           engineSettings: .object(["options": .array(options)]), seed: 77, appVersion: "1.0")
        g.moves = ["e2e4", "e7e5"]
        g.result = result
        g.ending = ending
        return g
    }

    func testAZeistGameCarriesOnlyTheGame() throws {
        let p = try XCTUnwrap(EngineGames.payload(game()))
        XCTAssertEqual(Set(p.keys), ["id", "engine", "engine_version", "level", "seed", "side", "start", "moves", "result", "end", "clock", "app", "rated"])
        XCTAssertEqual(p["level"] as? Int, 3, "the engine's own level, not the app's")
        XCTAssertEqual(p["seed"] as? UInt32, 77)
        XCTAssertEqual(p["moves"] as? String, "e2e4 e7e5")
        XCTAssertTrue(p["start"] is NSNull)
        XCTAssertTrue(p["clock"] is NSNull)
        XCTAssertEqual(p["app"] as? String, "zeist-chess-ios")
        XCTAssertEqual(p["rated"] as? Bool, false)
        XCTAssertEqual((p["id"] as? String)?.count, 36)
    }

    func testWhatIsNotShared() {
        XCTAssertNil(EngineGames.payload(game(engine: "stockfish-lite")), "only games against the Zeist engine")
        XCTAssertNil(EngineGames.payload(game(ending: "abandoned")))
        XCTAssertNil(EngineGames.payload(game(ending: nil, result: nil)), "not an unfinished game")
        XCTAssertNil(EngineGames.payload(game(ending: "timeout")), "a flag only falls with a clock")
    }

    func testEndingsAndAnOlderGameWithoutASeed() throws {
        XCTAssertEqual(try XCTUnwrap(EngineGames.payload(game(ending: "insufficient", result: "1/2-1/2")))["end"] as? String, "material")
        var timed = game(ending: "timeout", result: "0-1")
        timed.timeControl = .minutes(3, 2)
        let p = try XCTUnwrap(EngineGames.payload(timed))
        XCTAssertEqual((p["clock"] as? [String: Int])?["base"], 180)
        XCTAssertEqual((p["clock"] as? [String: Int])?["inc"], 2)
        XCTAssertTrue(try XCTUnwrap(EngineGames.payload(game(seed: nil)))["seed"] is NSNull)
    }

    func testTheAccountsChoiceCounts() throws {
        XCTAssertEqual(EngineGames.say(signedIn: false, archive: nil), .send, "signed out, this iPhone's switch decides")
        XCTAssertEqual(EngineGames.say(signedIn: false, archive: false), .send)
        XCTAssertEqual(EngineGames.say(signedIn: true, archive: true), .send)
        XCTAssertEqual(EngineGames.say(signedIn: true, archive: false), .never, "an account that said no is never sent from")
        XCTAssertEqual(EngineGames.say(signedIn: true, archive: nil), .hold, "not known means wait")
    }

    func testOnlyAPlainYesOrNoIsAChoice() throws {
        func me(_ json: String) throws -> Account.Me { try JSONDecoder().decode(Account.Me.self, from: Data(json.utf8)) }
        XCTAssertEqual(try me(#"{"owner":"a","chess_archive":false}"#).chess_archive, false)
        XCTAssertEqual(try me(#"{"owner":"a","chess_archive":true}"#).chess_archive, true)
        XCTAssertNil(try me(#"{"owner":"a"}"#).chess_archive)
        XCTAssertNil(try me(#"{"owner":"a","chess_archive":"no"}"#).chess_archive)
        XCTAssertNil(try me(#"{"owner":"a","chess_archive":0}"#).chess_archive)
        XCTAssertNil(try me(#"{"owner":"a","chess_archive":null}"#).chess_archive)
        XCTAssertEqual(try me(#"{"owner":"a","chess_archive":1}"#).owner, "a", "an odd value doesn't lose the account")
    }

    func testAGameWaitsForItsOwnAccountsYes() throws {
        func v(_ by: String?, session: Bool, owner: String? = nil, archive: Bool? = nil, fresh: Bool = true) -> EngineGames.Verdict {
            EngineGames.verdict(by: by, session: session, owner: owner, archive: archive, fresh: fresh)
        }
        XCTAssertEqual(v(nil, session: false), .send, "played signed out: this iPhone's switch decides")
        XCTAssertEqual(v(nil, session: true, owner: "a", archive: false), .send, "and it was never that account's game")
        XCTAssertEqual(v("a", session: true, owner: "a", archive: true), .send)
        XCTAssertEqual(v("a", session: true, owner: "a", archive: false), .drop)
        XCTAssertEqual(v("a", session: true, owner: "a", archive: nil), .keep)
        XCTAssertEqual(v("a", session: true, owner: "a", archive: true, fresh: false), .keep, "a remembered yes isn't enough")
        XCTAssertEqual(v("a", session: false), .keep, "signed out since: it isn't sent on the switch alone")
        XCTAssertEqual(v("a", session: true, owner: "b", archive: true), .keep, "another account's yes doesn't release it")
        XCTAssertEqual(v("a", session: true, owner: nil, archive: true), .keep)
    }

    func testTheMarkIsNeverSent() throws {
        var p = try XCTUnwrap(EngineGames.payload(game()))
        let plain = Set(p.keys)
        p[EngineGames.mark] = "owner-1"
        XCTAssertEqual(Set(EngineGames.sent(p).keys), plain)
        XCTAssertFalse(String(data: try JSONSerialization.data(withJSONObject: EngineGames.sent(p)), encoding: .utf8)!.contains("owner-1"))
    }

    func testSharingStartsOffInATestRunAndFollowsTheSwitch() throws {
        let d = UserDefaults.standard, was = d.object(forKey: EngineGames.key)
        defer { if let was { d.set(was, forKey: EngineGames.key) } else { d.removeObject(forKey: EngineGames.key) } }
        d.removeObject(forKey: EngineGames.key)
        XCTAssertFalse(EngineGames.startsOn, "a test run never starts sending")
        XCTAssertEqual(EngineGames.on, EngineGames.startsOn, "untouched, the switch is where it starts")
        d.set(true, forKey: EngineGames.key); XCTAssertTrue(EngineGames.on)
        d.set(false, forKey: EngineGames.key); XCTAssertFalse(EngineGames.on)
    }
}
