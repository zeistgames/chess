import Foundation
import Observation

/// One game, kept on the device for good: enough to replay it, rate it and review it later.
struct GameRecord: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var startedAt = Date()
    var endedAt: Date?
    var startFEN: String
    /// The position now (after the last move), for drawing the game without asking the rules.
    var fen: String
    var moves: [String] = []
    var san: [String] = []
    /// "1-0", "0-1", "1/2-1/2", or "*" for a game abandoned unfinished. Nil while it goes on.
    var result: String?
    /// checkmate, stalemate, repetition, fifty-move, insufficient, resigned, timeout (a flag fell),
    /// timeout-insufficient (a flag fell but the other side could not checkmate: a draw), agreement (a draw offered
    /// and accepted), engine-resigned (the engine gave up a lost game) or abandoned.
    var ending: String?
    /// The player's side: "w" or "b".
    var player: String
    var engineID: String
    var engineName: String
    var engineVersion: String
    var packSHA: String?
    var level: Int
    var adaptive: Bool
    /// Set when the player chose the engine's rating by hand; the number is on the engine's own scale.
    var rating: Int?
    /// "Rating 1500", "Level 4" or "Level 4, adaptive".
    var difficulty: String { rating.map { "Rating \($0)" } ?? "Level \(level)\(adaptive ? ", adaptive" : "")" }
    /// Exactly what was sent to the engine (core/levels.js settings): options, node budget, MultiPV, the seed.
    var engineSettings: JSONValue?
    var seed: UInt32
    var undos = 0
    /// The clock, when the game has one. Nil for a game without a clock.
    var timeControl: TimeControl?
    /// bullet, blitz, rapid or classical, from the time control, so ratings per kind can be worked out later.
    var timeClass: String?
    /// Each side's time left after each move, in milliseconds, increment included: clocks[i] belongs to moves[i].
    var clocks: [Int]?
    /// White's and Black's time left when the game was last saved, in milliseconds. A game picked up again
    /// resumes from here.
    var clockLeft: [Int]?
    /// The opening the game went into, by the Lichess openings table: "B20" and "Sicilian Defense".
    var openingECO: String?
    var openingName: String?
    /// How many hints the player asked for. A game with hints never moves the adaptive level up.
    var hints: Int?
    var appVersion: String
    /// The Zeist account this game belongs to (its owner tag, from /api/me), once signed in.
    var account: String?
    var accountHandle: String?
    /// Sending to the player's Zeist profile: nil while there's nothing to send, "waiting" once a finished game
    /// belongs to an account, "sent" once Zeist has it. Nothing is sent in this version: Zeist has no endpoint yet.
    var upload: String?
    var sentAt: Date?

    /// Started from Learn ("Learn as you play"): only such a game shows cards. Kept with the game, so it stays one
    /// when picked up again and is marked so in Games.
    var learn: Bool?
    /// Human mode: the engine has asked for a draw in this game (it asks once).
    var engineAskedDraw: Bool?

    var finished: Bool { result != nil }

    /// Started from a position the player chose rather than the usual start. Never counts toward adaptive play.
    var fromPosition: Bool { startFEN != "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1" }

    /// From the player's side.
    var outcome: String? {
        guard let result else { return nil }
        switch result {
        case "1-0": return player == "w" ? "win" : "loss"
        case "0-1": return player == "b" ? "win" : "loss"
        case "1/2-1/2": return "draw"
        default: return nil
        }
    }

    static var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }
}

/// Every game, one JSON file each in Application Support/games, written at every move.
@MainActor @Observable
final class GameLog {
    static let shared = GameLog()
    static let folder = Places.support.appending(path: "games", directoryHint: .isDirectory)

    /// Every game kept on this device, whoever played it.
    private(set) var all: [GameRecord] = []
    /// Whose games are shown: the account signed in, or nil for a guest. Replaceable in tests.
    var viewer: @MainActor () -> String? = { Account.shared.owner }
    /// The games of whoever is signed in, and only those; signed out, only guest games. On a shared phone another
    /// account's games stay stored and come back when it signs in.
    var games: [GameRecord] { let v = viewer(); return all.filter { $0.account == v } }
    /// Whether a game belongs to whoever is signed in now, so it may count anywhere (Game Center, Measure, sharing).
    func countsHere(_ g: GameRecord) -> Bool { g.account == viewer() }

    private init() { load() }

    func load() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        let d = Self.decoder
        all = files.filter { $0.pathExtension == "json" }
            .compactMap { try? d.decode(GameRecord.self, from: Data(contentsOf: $0)) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// The game still going, if any.
    var current: GameRecord? { games.first { !$0.finished } }
    var finished: [GameRecord] { games.filter(\.finished) }

    func save(_ r: GameRecord) { save(r, owner: Account.shared.owner, handle: Account.shared.handle) }

    /// A game belongs to the account it was started under, kept by this log: a copy saved without an owner never
    /// clears it, and an account's game never passes to another. A game started signed out is claimed once, by the
    /// first account that signs in (stamp).
    func save(_ r: GameRecord, owner: String?, handle: String?) {
        var r = r
        if let kept = all.first(where: { $0.id == r.id }) {
            if kept.account != nil { r.account = kept.account; r.accountHandle = kept.accountHandle }
        } else if r.account == nil, let owner {
            r.account = owner; r.accountHandle = handle
        }
        if r.finished, r.ending != "abandoned", r.account != nil, r.upload == nil { r.upload = "waiting" }
        if let i = all.firstIndex(where: { $0.id == r.id }) { all[i] = r } else { all.insert(r, at: 0) }
        do { try Self.encoder.encode(r).write(to: Self.folder.appending(path: "\(r.id.uuidString).json"), options: .atomic) } catch {
            print("game log: could not write \(r.id): \(error)")
        }
    }

    /// Games played signed out move to the account at sign-in: every guest game on this device, finished or not, joins
    /// whoever signs in first, as a guest's puzzle progress does (the rule Zeist and Zeist Chess share). The consequence
    /// on a shared device: games someone else played there signed out become the account's, and once claimed they stay
    /// that account's (save never moves an owned game). Signing out doesn't give them back.
    func stamp(owner: String, handle: String?) {
        for g in all where g.account == nil {
            var g = g
            g.account = owner
            g.accountHandle = handle
            save(g)
        }
    }

    /// An account that was deleted leaves its games on this device as a guest's, so they stay in the list. The one
    /// place a game loses its owner; like any guest game, they join the next account to sign in.
    func release(owner: String) {
        for (i, g) in all.enumerated() where g.account == owner {
            var g = g
            g.account = nil
            g.accountHandle = nil
            if g.upload == "waiting" { g.upload = nil }
            all[i] = g
            do { try Self.encoder.encode(g).write(to: Self.folder.appending(path: "\(g.id.uuidString).json"), options: .atomic) } catch {
                print("game log: could not write \(g.id): \(error)")
            }
        }
    }

    // MARK: Sending to Zeist

    /// Finished games that belong to an account and haven't reached Zeist yet, oldest first.
    var waiting: [GameRecord] { games.filter { $0.upload == "waiting" }.sorted { $0.startedAt < $1.startedAt } }

    /// Where finished games will go on Zeist. None exists yet, so this stays nil and nothing calls send(_:).
    static let uploadEndpoint: URL? = nil

    /// Sends one finished game to its account on Zeist and marks it sent. Not wired to anything yet: once Zeist
    /// has an endpoint, set uploadEndpoint and call this for each game in waiting (after sign-in, after a game).
    func send(_ id: UUID) async throws {
        guard let url = Self.uploadEndpoint else { throw PackError("Zeist has no endpoint for games yet.") }
        guard var g = games.first(where: { $0.id == id }), g.upload == "waiting", let token = Keychain.token,
              g.account == Account.shared.owner else { return }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try Self.encoder.encode(g)
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let h = response as? HTTPURLResponse, (200..<300).contains(h.statusCode) else { throw URLError(.badServerResponse) }
        g.upload = "sent"
        g.sentAt = Date()
        save(g)
    }

    /// Ends an unfinished game without a result, so it stays in the log.
    func abandon(_ id: UUID) {
        guard var g = all.first(where: { $0.id == id }), !g.finished else { return }
        g.result = "*"
        g.ending = "abandoned"
        g.endedAt = Date()
        save(g)
    }

    nonisolated static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, enc in
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var c = enc.singleValueContainer(); try c.encode(f.string(from: date))
        }
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    nonisolated static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d }
            f.formatOptions = [.withInternetDateTime]
            if let d = f.date(from: s) { return d }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "date \(s)"))
        }
        return d
    }()

    // MARK: Export

    /// The whole log as JSON, one record per game.
    func exportJSON() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "Zeist Chess games.json")
        try Self.encoder.encode(games.sorted { $0.startedAt < $1.startedAt }).write(to: url, options: .atomic)
        return url
    }

    /// The whole log as PGN.
    func exportPGN() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "Zeist Chess games.pgn")
        try games.sorted { $0.startedAt < $1.startedAt }.map(Self.pgn).joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    nonisolated static func pgn(_ g: GameRecord) -> String {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy.MM.dd"
        let you = g.accountHandle ?? "You"
        let them = "\(g.engineName) \(g.engineVersion), level \(g.level)"
        var tags: [(String, String)] = [
            ("Event", "Zeist Chess"), ("Site", "iPhone"), ("Date", day.string(from: g.startedAt)), ("Round", "-"),
            ("White", g.player == "w" ? you : them), ("Black", g.player == "w" ? them : you),
            ("Result", g.result ?? "*"),
        ]
        if g.startFEN != "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1" { tags += [("SetUp", "1"), ("FEN", g.startFEN)] }
        if let eco = g.openingECO, let name = g.openingName { tags += [("ECO", eco), ("Opening", name)] }
        if let e = g.ending { tags.append(("Termination", e.hasPrefix("timeout") ? "time forfeit" : e)) }
        tags.append(("TimeControl", g.timeControl?.pgn ?? "-"))
        tags.append(("Annotator", "Zeist Chess \(g.appVersion)"))
        var head = tags.map { "[\($0.0) \"\($0.1.replacingOccurrences(of: "\"", with: "'"))\"]" }.joined(separator: "\n")
        head += "\n\n"
        let blackFirst = g.startFEN.split(separator: " ").dropFirst().first == "b"
        let startNo = Int(g.startFEN.split(separator: " ").last ?? "1") ?? 1
        var body: [String] = []
        for (i, s) in g.san.enumerated() {
            let ply = i + (blackFirst ? 1 : 0)
            let no = startNo + ply / 2
            if ply % 2 == 0 { body.append("\(no). \(s)") } else if i == 0 { body.append("\(no)... \(s)") } else { body.append(s) }
            if let c = g.clocks, c.indices.contains(i) { body.append("{[%clk \(ChessClock.pgn(ms: c[i]))]}") }
        }
        body.append(g.result ?? "*")
        var lines: [String] = []
        var line = ""
        for w in body {
            if line.count + w.count + 1 > 79 { lines.append(line); line = w } else { line = line.isEmpty ? w : line + " " + w }
        }
        if !line.isEmpty { lines.append(line) }
        return head + lines.joined(separator: "\n") + "\n"
    }
}
