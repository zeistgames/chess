import XCTest
@testable import ZeistChess

/// Rated games through Zeist: the start (one game per start id, the seed from /ack), the finish kept until Zeist
/// answers, and the readings kept for the chart. Never reaches Zeist: the network is replaced.
@MainActor
final class RatedTests: XCTestCase {
    private var saved: (net: (URLRequest) async throws -> (Data, Int), who: () -> (token: String, owner: String)?, defaults: UserDefaults)!
    private var sent: [(method: String, path: String, body: [String: Any])] = []

    override func setUp() async throws {
        saved = (Rated.net, Rated.who, Rated.defaults)
        let suite = "rated-tests-\(UUID().uuidString)"
        Rated.defaults = UserDefaults(suiteName: suite)!
        Rated.who = { ("token", "owner-A") }
        sent = []
    }

    override func tearDown() async throws {
        Rated.net = saved.net; Rated.who = saved.who; Rated.defaults = saved.defaults
    }

    /// Answers each request with the next (body, status); a nil body stands for no answer at all (offline).
    private func answer(_ replies: [(String?, Int)]) {
        var queue = replies
        Rated.net = { [unowned self] req in
            let body = req.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            let path = req.url!.path + (req.url!.query.map { "?\($0)" } ?? "")
            self.sent.append((req.httpMethod ?? "GET", path, body))
            let (b, status) = queue.isEmpty ? (#"{}"#, 500) : queue.removeFirst()
            guard let b else { throw URLError(.notConnectedToInternet) }
            return (Data(b.utf8), status)
        }
    }

    func testAStartIsAcknowledgedForItsSeed() async throws {
        answer([(#"{"ok":true,"id":"abcdef0123456789abcd","level":{"level":3},"seat":1}"#, 200),
                (#"{"ok":true,"id":"abcdef0123456789abcd","level":{"level":3},"seed":4000000000,"seat":1}"#, 200)])
        let g = try await Rated.start(level: nil, seat: 1)
        XCTAssertEqual(g, Rated.Issued(id: "abcdef0123456789abcd", level: 3, seed: 4_000_000_000, seat: 1))
        XCTAssertEqual(sent.map(\.path), ["/api/rated", "/api/rated/abcdef0123456789abcd/ack"])
        XCTAssertEqual(sent[0].body["game"] as? String, "chess")
        XCTAssertNil(sent[0].body["level"], "Matched leaves the level to Zeist")
        XCTAssertEqual(sent[0].body["seat"] as? Int, 1)
    }

    func testAStartWithNoAnswerIsSentAgainWithTheSameID() async throws {
        answer([(nil, 0), (#"{"ok":true,"id":"abcdef0123456789abcd","level":{"level":5},"seed":7,"seat":0}"#, 200), (#"{"ok":true,"id":"x","level":{"level":5},"seed":8,"seat":0}"#, 200)])
        do { _ = try await Rated.start(level: 5, seat: 0); XCTFail("no answer") } catch {}
        _ = try await Rated.start(level: 5, seat: 0)
        let first = sent[0].body["start"] as? String, second = sent[1].body["start"] as? String
        XCTAssertNotNil(first)
        XCTAssertEqual(first, second, "the same start, so Zeist answers with the same game")
        XCTAssertEqual(sent[1].body["level"] as? Int, 5)
        _ = try await Rated.start(level: 5, seat: 0)
        XCTAssertNotEqual(sent[2].body["start"] as? String, first, "once answered, the next game is a fresh start")
    }

    func testAFinishIsKeptUntilZeistAnswers() async {
        answer([(nil, 0), (#"{"error":"unavailable"}"#, 503), (#"{"error":"owner"}"#, 403), (#"{"ok":true,"outcome":"win"}"#, 200)])
        let moves = ["e2e4", "e7e5"]
        var r = await RatedFinishes.send("g1", moves: moves, resign: false, owner: "owner-A")
        XCTAssertEqual(r, .waiting)
        await RatedFinishes.flush()
        await RatedFinishes.flush()
        XCTAssertEqual(RatedFinishes.queued.map(\.id), ["g1"], "offline, Zeist's trouble and another account's tag all keep it")
        r = await RatedFinishes.send("g1", moves: ["a2a3"], resign: true, owner: "owner-A")
        XCTAssertEqual(r, .counted)
        XCTAssertTrue(RatedFinishes.queued.isEmpty)
        XCTAssertEqual(sent.last?.body["moves"] as? [String], moves, "the first finish kept is the one sent")
        XCTAssertEqual(sent.last?.body["owner"] as? String, "owner-A")
    }

    func testZeistsAnswersAreReadAsItsDocsSay() async {
        answer([(#"{"error":"over"}"#, 409), (#"{"error":"computer"}"#, 400), (#"{"error":"not_found"}"#, 404),
                (#"{"ok":true,"pending":true}"#, 200), (#"{}"#, 408)])
        let over = await RatedFinishes.send("g2", moves: [], resign: true, owner: "owner-A")
        XCTAssertEqual(over, .counted, "409 over: settled already (a lost answer) or forfeited, so it counted")
        let failed = await RatedFinishes.send("g3", moves: [], resign: true, owner: "owner-A")
        XCTAssertEqual(failed, .counted, "a failed check is a loss Zeist records")
        let missing = await RatedFinishes.send("g4", moves: [], resign: true, owner: "owner-A")
        XCTAssertEqual(missing, .refused)
        let pending = await RatedFinishes.send("g5", moves: [], resign: true, owner: "owner-A")
        XCTAssertEqual(pending, .pending)
        XCTAssertTrue(RatedFinishes.queued.isEmpty)
        let other = await RatedFinishes.send("g6", moves: [], resign: true, owner: "owner-A")
        XCTAssertEqual(other, .waiting, "any other status is tried again")
        XCTAssertEqual(RatedFinishes.queued.map(\.id), ["g6"])
    }

    func testAnAckForAGameThatEndedStartsOnceMoreFresh() async throws {
        answer([(#"{"ok":true,"id":"aaaaaaaaaaaaaaaaaaaa","level":{"level":3},"seat":0}"#, 200), (#"{"error":"over"}"#, 409),
                (#"{"ok":true,"id":"bbbbbbbbbbbbbbbbbbbb","level":{"level":3},"seat":0}"#, 200),
                (#"{"ok":true,"id":"bbbbbbbbbbbbbbbbbbbb","level":{"level":3},"seed":9,"seat":0}"#, 200)])
        let g = try await Rated.start(level: 3, seat: 0)
        XCTAssertEqual(g.id, "bbbbbbbbbbbbbbbbbbbb")
        XCTAssertNotEqual(sent[0].body["start"] as? String, sent[2].body["start"] as? String, "a fresh start id the second time")
    }

    func testALostAckIsAskedForAgain() async throws {
        answer([(#"{"ok":true,"id":"aaaaaaaaaaaaaaaaaaaa","level":{"level":3},"seat":0}"#, 200), (nil, 0), (#"{}"#, 503),
                (#"{"ok":true,"id":"aaaaaaaaaaaaaaaaaaaa","level":{"level":3},"seed":5,"seat":0}"#, 200)])
        let g = try await Rated.start(level: 3, seat: 0)
        XCTAssertEqual(g.seed, 5)
        XCTAssertEqual(sent.filter { $0.path.hasSuffix("/ack") }.count, 3)
    }

    func testAnotherAccountsFinishWaitsForIt() async {
        answer([])
        Rated.who = { ("token", "owner-B") }
        let r = await RatedFinishes.send("g4", moves: [], resign: true, owner: "owner-A")
        XCTAssertEqual(r, .waiting)
        XCTAssertTrue(sent.isEmpty, "never sent under the account signed in now")
        XCTAssertEqual(RatedFinishes.queued.count, 1)
    }

    func testReadingsAreKeptOnlyOnceRankedAndWhenTheyMove() {
        let book = RatingBook()
        book.note(Rated.Standing(rating: nil, games: 4, level: 2), owner: "owner-A")
        XCTAssertTrue(book.readings.isEmpty, "no number before ten games")
        book.note(Rated.Standing(rating: 1482, games: 10, rank_name: "Amateur"), owner: "owner-A")
        book.note(Rated.Standing(rating: 1482, games: 10), owner: "owner-A")
        book.note(Rated.Standing(rating: 1496, games: 11), owner: "owner-A")
        XCTAssertEqual(book.readings.map(\.rating), [1482, 1496])
        XCTAssertEqual(book.highest, 1496)
        Rated.who = { ("token", "owner-B") }
        XCTAssertTrue(book.readings.isEmpty, "each account has its own")
        XCTAssertNil(book.current)
    }

    func testAStandingDecodesWithAndWithoutTheRecord() throws {
        let a = try JSONDecoder().decode(Rated.Standing.self, from: Data(#"{"ok":true,"game":"chess","games":3,"rank":0,"rank_level":0,"rank_name":"New","until_ranked":7,"level":2}"#.utf8))
        XCTAssertFalse(a.ranked); XCTAssertNil(a.record); XCTAssertEqual(a.level, 2)
        let b = try JSONDecoder().decode(Rated.Standing.self, from: Data(#"{"ok":true,"rating":1496,"games":62,"rank_level":3,"rank_name":"Amateur","until_ranked":0,"level":3,"record":{"won":31,"drawn":6,"lost":25}}"#.utf8))
        XCTAssertEqual(b.rating, 1496); XCTAssertEqual(b.record, .init(won: 31, drawn: 6, lost: 25))
    }

    func testARatedGameHasNoUndoHintsOrDrawOffers() throws {
        let engine = try XCTUnwrap(Shelf.shared.engine(Rated.engineID) ?? Shelf.shared.engine(Shelf.bundledID))
        var rec = GameRecord(startFEN: GameModel.standardStart, fen: GameModel.standardStart, player: "w", engineID: engine.id, engineName: engine.name,
                             engineVersion: "1", level: 3, adaptive: false, seed: 1, appVersion: "t")
        rec.moves = ["e2e4", "e7e5"]
        let plain = GameModel(record: rec, engine: engine)
        XCTAssertTrue(plain.canUndo)
        XCTAssertTrue(plain.canOfferDraw)
        rec.ratedID = "abcdef0123456789abcd"; rec.ratedBy = "owner-A"
        let rated = GameModel(record: rec, engine: engine)
        XCTAssertFalse(rated.canUndo)
        XCTAssertFalse(rated.canHint)
        XCTAssertFalse(rated.canOfferDraw)
        XCTAssertEqual(rec.difficulty, "Rated, level 3")
    }
}
