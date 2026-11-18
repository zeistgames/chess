import Foundation
import Observation
import UIKit

/// A card as core/learn/cards.js gives it: what came up, the move it is about, and when it may be shown.
struct PlayCard: Decodable, Equatable, Sendable {
    let key: String
    let kind: String
    let side: String
    let ply: Int
    let shows: Int
    let title: String
    let line: String?
    let name: String?
}

/// A card with the lesson it opens, ready to show. Openings take their chapter's title and line.
struct ShownCard: Equatable, Identifiable {
    let card: PlayCard
    let route: Route
    let title: String
    let line: String
    /// One per thing: the kind, or the opening chapter.
    let key: String
    var id: String { key }
    var isOpening: Bool { card.kind == "opening" }
    /// The words on the way to the lesson.
    var link: String
}

/// Learn as you play: which lesson a card opens (core/learn/lessons.json, and the openings course by title), and
/// asking core for the cards of a game. The rules themselves live in core/learn/cards.js, run in the app's web view,
/// so the app and the web name the same things at the same moments.
@MainActor
enum LearnPlay {
    /// The kind of card to the lesson it opens, as data.
    static let table: [String: String] = {
        let url = Places.core.appending(path: "learn/lessons.json")
        guard let d = try? Data(contentsOf: url), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let l = o["lessons"] as? [String: String] else { return [:] }
        return l
    }()

    /// The cards of a game so far, from core. Empty for a game not started from Learn.
    static func cards(moves: [String], player: String, fen: String, learn: Bool, over: Bool) async -> [PlayCard] {
        guard learn else { return [] }
        let args: [String: Any] = ["moves": moves, "player": player, "fen": fen, "learn": learn, "over": over]
        guard let d = try? await Core.shared.module("./learn/cards.js", "cards", args) else { return [] }
        return (try? JSONDecoder().decode([PlayCard].self, from: d)) ?? []
    }

    /// The lesson a card opens, with the words to show; nil when there is no lesson for it (then it is not shown).
    static func resolve(_ c: PlayCard, library: LessonLibrary = .shared) -> ShownCard? {
        if c.kind == "opening" {
            guard let name = c.name, let openings = library.course("openings"), let ch = chapter(for: name, in: openings) else { return nil }
            return ShownCard(card: c, route: .chapter("openings", ch.id), title: ch.title, line: ch.line ?? "The game reached this opening.",
                             key: "opening:" + ch.id, link: "The opening")
        }
        guard let id = table[c.kind], let entry = library.entry(id) else { return nil }
        return ShownCard(card: c, route: .lesson(id), title: c.title, line: c.line ?? "", key: c.kind, link: entry.title)
    }

    /// The opening chapter for a name from the opening table, by the same rule as core/learn/lessons.js: the title is
    /// the whole name, its beginning, one of its ": " parts, or the start of a part before a comma; the longest title
    /// wins, then the one further into the name. Chapters added to the index are picked up with no change here.
    static func chapter(for name: String, in openings: LessonIndex.Course) -> LessonIndex.Chapter? {
        let parts = name.components(separatedBy: ": ")
        var best: (LessonIndex.Chapter, Int)?
        for ch in openings.chapters {
            let t = ch.title
            var at = -1
            if name == t || name.hasPrefix(t + ":") || name.hasPrefix(t + " ") { at = 0 }
            for (i, p) in parts.enumerated() where p == t || p.hasPrefix(t + ",") { at = max(at, i) }
            guard at >= 0 else { continue }
            if let b = best, t.count < b.0.title.count || (t.count == b.0.title.count && at <= b.1) { continue }
            best = (ch, at)
        }
        return best?.0
    }
}

/// The cards of one game: the one showing, those waiting their turn, and everything that came up (for the end of the
/// game). One at a time, in order: each stays until the next move or until put away, then the next comes. What has
/// been shown is kept with the game, so a card never comes back, even after the app is closed; a move taken back
/// takes its card back with it, so it can come again if it happens again.
@MainActor @Observable
final class GameCards {
    private(set) var current: ShownCard?
    private(set) var waiting: [ShownCard] = []
    private(set) var found: [ShownCard] = []
    /// Each card shown, by key, to the move that settled it (its `shows`): a card is shown only once it is on the
    /// screen, and taking back any move it rests on takes it back.
    private var shown: [String: Int]
    private var shownAt = 0
    private var moves = 0
    private let gameID: UUID
    private let defaults: UserDefaults
    private var asked = 0

    /// One for each game while the app runs, so leaving for a lesson and coming back finds it as it was.
    private static var all: [UUID: GameCards] = [:]
    static func of(_ id: UUID) -> GameCards {
        if let c = all[id] { return c }
        let c = GameCards(gameID: id)
        all[id] = c
        return c
    }

    private var storeKey: String { "learn.shown.\(gameID.uuidString)" }

    init(gameID: UUID, defaults: UserDefaults = .standard) {
        self.gameID = gameID
        self.defaults = defaults
        shown = (defaults.dictionary(forKey: "learn.shown.\(gameID.uuidString)") as? [String: Int]) ?? [:]
    }

    /// Asks core what is due after these moves, and lines up what has not been shown.
    func update(moves list: [String], player: String, fen: String, learn: Bool, over: Bool,
                cards: (([String], String, String, Bool, Bool) async -> [PlayCard])? = nil) async {
        asked += 1
        let ask = asked
        let got: [PlayCard]
        if let cards { got = await cards(list, player, fen, learn, over) }
        else { got = await LearnPlay.cards(moves: list, player: player, fen: fen, learn: learn, over: over) }
        guard ask == asked else { return }
        let n = list.count
        if n < moves {
            // Moves taken back: cards resting on any of them go, and may come again.
            shown = shown.filter { $0.value <= n }
            waiting.removeAll { $0.card.shows > n }
            if let c = current, c.card.shows > n { current = nil }
        } else if n > moves, current != nil, shownAt < n {
            current = nil   // a card stays until the next move
        }
        moves = n
        var keys = Set<String>()
        found = got.compactMap { LearnPlay.resolve($0) }.filter { keys.insert($0.key).inserted }
        for c in found where c.card.shows <= n && shown[c.key] == nil && current?.key != c.key && !waiting.contains(where: { $0.key == c.key }) {
            waiting.append(c)
        }
        if current == nil { next() }
    }

    func dismiss() {
        current = nil
        next()
    }

    private func next() {
        guard !waiting.isEmpty else { return }
        let c = waiting.removeFirst()
        current = c
        shownAt = moves
        shown[c.key] = c.card.shows
        defaults.set(shown, forKey: storeKey)
        if UIAccessibility.isVoiceOverRunning {
            let s = NSAttributedString(string: "\(c.title). \(c.line)", attributes: [.accessibilitySpeechAnnouncementPriority: UIAccessibilityPriority.low])
            UIAccessibility.post(notification: .announcement, argument: s)
        }
    }
}
