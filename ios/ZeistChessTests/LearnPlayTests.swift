import XCTest
@testable import ZeistChess

/// Learn as you play in the app: the shared cases (core/learn/cases.json, the same file core's node tests read) run
/// through the app's own path to core/learn/cards.js, and what a game shows from them.
@MainActor
final class LearnPlayTests: XCTestCase {
    struct Cases: Decodable {
        struct Case: Decodable {
            let name: String; let player: String; let moves: [String]; let fen: String?; let learn: Bool?; let over: Bool?
            let cards: [Card]
        }
        struct Card: Decodable, Equatable { let kind: String; let side: String; let ply: Int; let shows: Int; let title: String; let line: String?; let name: String? }
        let cases: [Case]
    }

    override func setUp() async throws { Core.shared.boot() }

    private func brief(_ c: [PlayCard]) -> [Cases.Card] { c.map { .init(kind: $0.kind, side: $0.side, ply: $0.ply, shows: $0.shows, title: $0.title, line: $0.line, name: $0.name) } }

    func testTheSharedCases() async throws {
        let url = Places.core.appending(path: "learn/cases.json")
        let all = try JSONDecoder().decode(Cases.self, from: Data(contentsOf: url)).cases
        XCTAssertFalse(all.isEmpty)
        for c in all {
            let fen = c.fen ?? GameModel.standardStart
            let got = await LearnPlay.cards(moves: c.moves, player: c.player, fen: fen, learn: c.learn ?? true, over: c.over ?? false)
            XCTAssertEqual(brief(got), c.cards, c.name)
            // Move by move: exactly the cards whose moment has come.
            for n in 0..<c.moves.count {
                let part = await LearnPlay.cards(moves: Array(c.moves.prefix(n)), player: c.player, fen: fen, learn: c.learn ?? true, over: false)
                XCTAssertEqual(brief(part), c.cards.filter { $0.shows <= n }, "\(c.name), after \(n) moves")
            }
        }
    }

    func testEveryLessonInTheTableExists() {
        XCTAssertFalse(LearnPlay.table.isEmpty, "core/learn/lessons.json is bundled")
        for (kind, id) in LearnPlay.table { XCTAssertNotNil(LessonLibrary.shared.lesson(id), "\(kind) opens \(id)") }
    }

    private func card(_ kind: String, shows: Int, name: String?) -> PlayCard {
        PlayCard(key: kind, kind: kind, side: "player", ply: 1, shows: shows, title: "T", line: "L.", name: name)
    }

    func testAnOpeningOpensItsChapterByTitle() throws {
        let openings = try XCTUnwrap(LessonLibrary.shared.course("openings"))
        let sicilian = try XCTUnwrap(openings.chapters.first { $0.title == "Sicilian Defense" })
        XCTAssertEqual(LearnPlay.chapter(for: "Sicilian Defense: Najdorf Variation", in: openings)?.id, sicilian.id)
        XCTAssertNil(LearnPlay.chapter(for: "Sicilian", in: openings))
        let shown = try XCTUnwrap(LearnPlay.resolve(card("opening", shows: 2, name: "Sicilian Defense")))
        XCTAssertEqual(shown.route, .chapter("openings", sicilian.id))
        XCTAssertNil(LearnPlay.resolve(card("opening", shows: 1, name: "Nowhere Opening")), "no chapter, no card")
        XCTAssertNil(LearnPlay.resolve(card("no-such-kind", shows: 1, name: nil)), "no lesson, no card")
        XCTAssertEqual(LearnPlay.resolve(card("fork", shows: 4, name: nil))?.route, .lesson("tactics-fork"))
    }

    private func card(_ kind: String, shows: Int, ply: Int) -> PlayCard {
        PlayCard(key: kind, kind: kind, side: "player", ply: ply, shows: shows, title: "T", line: "L.", name: nil)
    }

    func testCardsComeOneAtATimeInOrderEachOnce() async {
        let d = UserDefaults(suiteName: "learn-play-\(UUID())")!
        let id = UUID()
        let list = [card("castling", shows: 3, ply: 3), card("fork", shows: 5, ply: 2), card("en-passant", shows: 9, ply: 9)]
        let fake: ([String], String, String, Bool, Bool) async -> [PlayCard] = { moves, _, _, _, _ in list }
        let m = { (n: Int) in Array(repeating: "m", count: n) }
        let g = GameCards(gameID: id, defaults: d)
        await g.update(moves: m(2), player: "w", fen: "", learn: true, over: false, cards: fake)
        XCTAssertNil(g.current, "nothing due yet")
        await g.update(moves: m(6), player: "w", fen: "", learn: true, over: false, cards: fake)
        XCTAssertEqual(g.current?.key, "castling", "the first in order")
        XCTAssertEqual(g.waiting.map(\.key), ["fork"], "the next waits its turn")
        g.dismiss()
        XCTAssertEqual(g.current?.key, "fork", "put away, the next comes")
        await g.update(moves: m(7), player: "w", fen: "", learn: true, over: false, cards: fake)
        XCTAssertNil(g.current, "a card stays until the next move")
        await g.update(moves: m(8), player: "w", fen: "", learn: true, over: false, cards: fake)
        XCTAssertNil(g.current, "and does not come back")
        XCTAssertEqual(g.found.map(\.key), ["castling", "fork", "en-passant"], "everything that came up, for the end")
        let again = GameCards(gameID: id, defaults: d)
        await again.update(moves: m(8), player: "w", fen: "", learn: true, over: false, cards: fake)
        XCTAssertNil(again.current, "nor after the app is closed")
    }

    func testUndoTakesTheCardBack() async {
        let d = UserDefaults(suiteName: "learn-play-\(UUID())")!
        var list = [card("castling", shows: 7, ply: 7)]
        let fake: ([String], String, String, Bool, Bool) async -> [PlayCard] = { moves, _, _, _, _ in list.filter { $0.shows <= moves.count } }
        let g = GameCards(gameID: UUID(), defaults: d)
        await g.update(moves: Array(repeating: "m", count: 7), player: "w", fen: "", learn: true, over: false, cards: fake)
        XCTAssertEqual(g.current?.key, "castling")
        await g.update(moves: Array(repeating: "m", count: 5), player: "w", fen: "", learn: true, over: false, cards: fake)
        XCTAssertNil(g.current, "the move it was about was taken back")
        list = [card("castling", shows: 7, ply: 7)]
        await g.update(moves: Array(repeating: "m", count: 7), player: "w", fen: "", learn: true, over: false, cards: fake)
        XCTAssertEqual(g.current?.key, "castling", "it can come again when it happens again")
    }

    func testNothingOutsideLearn() async {
        let none = await LearnPlay.cards(moves: ["e2e4", "c7c5"], player: "w", fen: GameModel.standardStart, learn: false, over: false)
        XCTAssertTrue(none.isEmpty)
    }
}
