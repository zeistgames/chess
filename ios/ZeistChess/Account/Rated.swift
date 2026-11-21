import Foundation
import Observation

/// Rated games against the Zeist engine, through Zeist's own rated games, so one account has one chess rating
/// wherever it plays: in Zeist and here. Zeist chooses the seed and keeps the game; this app plays the Zeist engine
/// at Zeist's level with that seed (the engine's code is Zeist's own, so Zeist's replay of the game matches), then
/// sends the moves. Zeist checks them, and the result counts.
///
/// The contract is Zeist's: a start sent again with the same id is the same game, the seed comes from /ack, and a
/// finish is kept on this iPhone until Zeist has answered it (Zeist's docs, "Rated starts" and "Rated finishes on
/// the device"). Signed in only. Zeist gives no number before ten rated games; this app shows the number after
/// that, and Zeist keeps showing only the name of the level it has reached.
enum Rated {
    static let game = "chess"
    /// Rated games are against this engine only.
    static let engineID = "zeist"
    /// Zeist's eight chess levels and their ratings (measured against Maia, 2026-11-15). Level n is Level n here.
    static let levelRatings = [910, 1080, 1280, 1600, 1820, 2040, 2150, 2290]
    static let levels = 1...8
    /// Rated games before Zeist gives a rating.
    static let untilRanked = 10

    static func rating(ofLevel n: Int) -> Int? { levelRatings.indices.contains(n - 1) ? levelRatings[n - 1] : nil }

    /// A refusal from Zeist (the status and its error word), or no answer at all (status 0).
    struct Failure: Error, Equatable { var status: Int; var error: String? }

    /// The network: a request and its answer (body and status). Replaced in tests, which never reach Zeist.
    @MainActor static var net: (URLRequest) async throws -> (Data, Int) = { req in
        let (data, response) = try await URLSession.shared.data(for: req)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
    /// Who is signed in: the session token and the account's owner tag. Replaced in tests.
    @MainActor static var who: () -> (token: String, owner: String)? = {
        guard let t = Keychain.token, let o = Account.shared.owner, Account.shared.handle != nil else { return nil }
        return (t, o)
    }
    /// Where starts and finishes are kept. Replaced in tests.
    @MainActor static var defaults = UserDefaults.standard

    @MainActor
    static func request(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> Data {
        guard let w = who() else { throw Failure(status: 401, error: "signin") }
        var req = URLRequest(url: URL(string: path, relativeTo: Account.base)!.absoluteURL, timeoutInterval: 20)
        req.httpMethod = method
        req.setValue("Bearer \(w.token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data, status: Int
        do { (data, status) = try await net(req) } catch { throw Failure(status: 0, error: nil) }
        guard (200..<300).contains(status) else {
            let e = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw Failure(status: status, error: e)
        }
        return data
    }

    // MARK: Standing

    /// GET /api/rated?game=chess: the account's chess standing. rating only once ranked (ten rated games);
    /// record (won, drawn, lost) once Zeist sends it.
    struct Standing: Codable, Equatable, Sendable {
        struct Record: Codable, Equatable, Sendable { var won: Int; var drawn: Int; var lost: Int }
        var rating: Int?
        var games: Int
        var rank_level: Int?
        var rank_name: String?
        var until_ranked: Int?
        /// The level Zeist would pick for the next game (Matched).
        var level: Int?
        var record: Record?
        var ranked: Bool { rating != nil }
    }

    @MainActor static func standing() async throws -> Standing {
        try JSONDecoder().decode(Standing.self, from: try await request("GET", "/api/rated?game=\(game)"))
    }

    // MARK: Starting

    /// A game Zeist has started: its id, the level (1 to 8), the seed for the engine, and the seat (0 plays White).
    struct Issued: Equatable, Sendable { var id: String; var level: Int; var seed: UInt32; var seat: Int }
    private struct Answer: Decodable {
        struct Level: Decodable { var level: Int? }
        var id: String; var level: Level; var seed: UInt32?; var seat: Int
    }

    /// Starts a rated game at a level (nil: Matched, Zeist picks) and a seat (nil: Zeist picks). A start whose answer
    /// was lost is sent again with the same start id and comes back as the same game, never a second one.
    @MainActor static func start(level: Int?, seat: Int?) async throws -> Issued {
        let key = "\(game)/\(level.map(String.init) ?? "matched")/\(seat.map(String.init) ?? "any")"
        do { return try await startOnce(key: key, level: level, seat: seat) } catch let f as Failure where f.error == "acked" {
            // The game the start id named had ended or wasn't this account's: once more, as a fresh start.
            return try await startOnce(key: key, level: level, seat: seat)
        }
    }

    @MainActor private static func startOnce(key: String, level: Int?, seat: Int?) async throws -> Issued {
        let sid = StartIDs.id(key)
        var body: [String: Any] = ["game": game, "start": sid]
        if let level { body["level"] = level }
        if let seat { body["seat"] = seat }
        let a: Answer
        do {
            a = try JSONDecoder().decode(Answer.self, from: try await request("POST", "/api/rated", body: body))
        } catch let f as Failure {
            if f.status >= 400 && f.status < 500 && f.status != 429 { StartIDs.drop(key) }
            throw f
        } catch {
            StartIDs.drop(key) // a 2xx that can't be read: the next try is a fresh start
            throw Failure(status: 200, error: "format")
        }
        var seed = a.seed
        if seed == nil {
            // The seed comes from /ack, which tells Zeist this iPhone has the game. Until it answers, the start id is
            // kept, so a retry returns the same game to acknowledge.
            var tries = 0
            while seed == nil {
                tries += 1
                do {
                    let b = try JSONDecoder().decode(Answer.self, from: try await request("POST", "/api/rated/\(a.id)/ack", body: [:]))
                    seed = b.seed
                    if seed == nil { throw Failure(status: 200, error: "format") }
                } catch let f as Failure where f.status == 404 || f.status == 409 {
                    StartIDs.drop(key)
                    throw Failure(status: f.status, error: "acked")
                } catch {
                    if tries >= 3 { throw error } // kept: a later try of this start acknowledges the same game
                }
            }
        }
        StartIDs.drop(key)
        guard let seed, let lv = a.level.level, levels.contains(lv), a.seat == 0 || a.seat == 1 else { throw Failure(status: 200, error: "format") }
        return Issued(id: a.id, level: lv, seed: seed, seat: a.seat)
    }

    /// One id per rated start, kept for an hour while no answer has come, so a retry is the same start.
    enum StartIDs {
        static let key = "rated.start"
        static let lifetime: TimeInterval = 3600
        @MainActor static func id(_ start: String, now: Date = Date()) -> String {
            var all = load().filter { now.timeIntervalSince1970 - $0.value.at < lifetime }
            if let k = all[start] { return k.id }
            let id = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
            all[start] = Kept(id: id, at: now.timeIntervalSince1970)
            save(all)
            return id
        }
        @MainActor static func drop(_ start: String) {
            var all = load()
            guard all.removeValue(forKey: start) != nil else { return }
            save(all)
        }
        struct Kept: Codable { var id: String; var at: Double }
        @MainActor private static func load() -> [String: Kept] {
            guard let d = defaults.data(forKey: key) else { return [:] }
            return (try? JSONDecoder().decode([String: Kept].self, from: d)) ?? [:]
        }
        @MainActor private static func save(_ a: [String: Kept]) { defaults.set(try? JSONEncoder().encode(a), forKey: key) }
    }
}

/// Finished rated games on their way to Zeist. Kept before the first send and sent again (at launch, on each return
/// to the app, at sign-in) until Zeist has answered. Only the account that played a game sends it.
enum RatedFinishes {
    struct Pending: Codable, Equatable { var id: String; var moves: [String]; var resign: Bool; var owner: String; var at: Double }
    static let key = "rated.pending"
    @MainActor private static var sending = false

    /// What came of a send. counted: Zeist has settled it. pending: Zeist has it and is still checking it.
    /// refused: Zeist won't count it (it ended already, a day passed, or the moves were refused). waiting: no answer
    /// yet, or another account is signed in; kept and sent again later.
    enum Sent: String, Codable, Sendable { case counted, pending, refused, waiting }

    @MainActor static func send(_ id: String, moves: [String], resign: Bool, owner: String) async -> Sent {
        if !load().contains(where: { $0.id == id }) {
            save(load() + [Pending(id: id, moves: moves, resign: resign, owner: owner, at: Date().timeIntervalSince1970)])
        }
        return await attempt(id)
    }

    /// Everything still waiting, for the account signed in.
    @MainActor static func flush() async {
        guard !sending, Rated.who() != nil else { return }
        sending = true
        defer { sending = false }
        for p in load() { _ = await attempt(p.id) }
    }

    @MainActor static var queued: [Pending] { load() }

    @MainActor private static func attempt(_ id: String) async -> Sent {
        guard let p = load().first(where: { $0.id == id }), let w = Rated.who(), w.owner == p.owner else { return .waiting }
        do {
            var body: [String: Any] = ["moves": p.moves, "owner": p.owner]
            if p.resign { body["resign"] = true }
            let data = try await Rated.request("POST", "/api/rated/\(p.id)", body: body)
            drop(id)
            let pending = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["pending"] as? Bool == true
            return await settled(id, pending ? .pending : .counted)
        } catch let f as Rated.Failure {
            // Zeist's answer, as docs/RESULTS.md in Zeist reads it. 409: already settled (an earlier send whose answer
            // was lost) or forfeited after a day, so it counted. 400: moves Zeist won't take, which it records as a
            // loss. 404: this account has no such game. Anything else (no answer, the session ended, another account's,
            // too many requests, Zeist's trouble, any other status): kept, and sent again later.
            switch f.status {
            case 409, 400: drop(id); return await settled(id, .counted)
            case 404: drop(id); return await settled(id, .refused)
            default: return .waiting
            }
        } catch {
            return .waiting
        }
    }

    /// Zeist has answered for a game: the game in the log says so, the standing is read again, and a game on the
    /// screen shows it, whether the answer came at the end of the game or later, from a resend.
    @MainActor private static func settled(_ id: String, _ sent: Sent) async -> Sent {
        guard var g = GameLog.shared.all.first(where: { $0.ratedID == id }) else { return sent }
        g.ratedSent = sent
        if sent == .counted, let by = g.ratedBy, Rated.who()?.owner == by, let s = await RatingBook.shared.refresh() {
            g.ratingAfter = s.rating
            g.ratedGames = s.games
            g.nextRatedLevel = s.level
        }
        GameLog.shared.save(g)
        Session.shared.game?.settled(g)
        return sent
    }

    @MainActor private static func drop(_ id: String) { save(load().filter { $0.id != id }) }
    @MainActor private static func load() -> [Pending] {
        guard let d = Rated.defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Pending].self, from: d)) ?? []
    }
    @MainActor private static func save(_ a: [Pending]) { Rated.defaults.set(try? JSONEncoder().encode(Array(a.suffix(50))), forKey: key) }
}

/// The account's chess standing as last read, and the ratings this iPhone has read over time (for the chart and the
/// highest), kept for each account. Zeist keeps no history of the number, so the chart is the readings: one after
/// each rated game here, and one whenever the rating has moved since (a game in Zeist).
@MainActor @Observable
final class RatingBook {
    static let shared = RatingBook()
    struct Reading: Codable, Equatable, Sendable { var at: Double; var rating: Int; var games: Int }
    struct Kept: Codable, Equatable { var standing: Rated.Standing?; var readings: [Reading] = [] }

    private(set) var kept: [String: Kept] = [:]
    private let key = "rated.book"
    static let chartLength = 40

    init() { load() }

    func load() {
        kept = (Rated.defaults.data(forKey: key)).flatMap { try? JSONDecoder().decode([String: Kept].self, from: $0) } ?? [:]
    }

    /// The standing of the account signed in, as last read.
    var current: Rated.Standing? { Rated.who().flatMap { kept[$0.owner]?.standing } }
    var readings: [Reading] { Rated.who().flatMap { kept[$0.owner]?.readings } ?? [] }
    /// The best rating this iPhone has seen the account hold.
    var highest: Int? { readings.map(\.rating).max() }

    /// Reads the standing for the account signed in and keeps it. Returns it, or nil without an answer.
    @discardableResult
    func refresh() async -> Rated.Standing? {
        guard let w = Rated.who() else { return nil }
        guard let s = try? await Rated.standing(), Rated.who()?.owner == w.owner else { return nil }
        note(s, owner: w.owner)
        return s
    }

    func note(_ s: Rated.Standing, owner: String, at: Date = Date()) {
        var k = kept[owner] ?? Kept()
        k.standing = s
        if let r = s.rating, k.readings.last.map({ $0.rating != r || $0.games != s.games }) ?? true {
            k.readings.append(Reading(at: at.timeIntervalSince1970, rating: r, games: s.games))
            k.readings = Array(k.readings.suffix(200))
        }
        kept[owner] = k
        Rated.defaults.set(try? JSONEncoder().encode(kept), forKey: key)
    }

    /// The highest level beaten in a rated game on this iPhone by the account signed in.
    func bestBeaten(in log: [GameRecord]) -> Int? {
        log.filter { $0.ratedID != nil && $0.outcome == "win" }.map(\.level).max()
    }
}
