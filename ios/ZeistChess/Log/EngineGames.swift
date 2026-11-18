import Foundation

/// Sharing games against the Zeist engine, to help it play better. On unless the player turns it off in Settings.
/// A shared game carries its moves, the level, the seed, the result and how it ended, the clock and the side
/// played: nothing about the player, no account, no device. Sent to Zeist with no cookie or token; the contract
/// is Zeist's (POST /api/chess/games). Games wait in a small queue on this iPhone until they are taken.
/// Signed in, the account's own choice on Zeist ("Help improve the chess computer") also counts, as it does in
/// Zeist: an account that said no is never sent from, and while its choice isn't known games wait.
@MainActor
enum EngineGames {
    static let key = "share.zeistGames"
    static let address = Hosts.page("api/chess/games")
    private static var sending = false

    static var on: Bool { UserDefaults.standard.object(forKey: key) == nil ? startsOn : UserDefaults.standard.bool(forKey: key) }

    /// What the switch says before the player has touched it: on. Test runs and scripted debug launches start
    /// off, so that games nobody played are not sent to Zeist.
    static var startsOn: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if NSClassFromString("XCTestCase") != nil || args.contains("-reset") || args.contains("-screen") { return false }
        #endif
        return true
    }

    enum Say: Equatable { case send, hold, never }
    /// What the account says about sending. Signed out, only this iPhone's switch decides.
    static func say(signedIn: Bool, archive: Bool?) -> Say {
        guard signedIn else { return .send }
        switch archive { case true?: return .send; case false?: return .never; case nil: return .hold }
    }
    static var say: Say { say(signedIn: Account.shared.hasSession, archive: Account.shared.me?.chess_archive) }

    /// What is sent for one game, or nil for a game that isn't shared (another engine, unfinished, too long).
    static func payload(_ g: GameRecord) -> [String: Any]? {
        guard g.engineID == "zeist", let result = g.result, let ending = g.ending, ending != "abandoned",
              ["1-0", "0-1", "1/2-1/2"].contains(result), g.moves.count <= 600 else { return nil }
        let ends = ["checkmate": "checkmate", "stalemate": "stalemate", "repetition": "repetition", "fifty-move": "fifty-move",
                    "insufficient": "material", "resigned": "resigned", "engine-resigned": "engine-resigned",
                    "timeout": "timeout", "agreement": "agreement"]
        guard let end = ends[ending], let level = engineLevel(g), (1...8).contains(level) else { return nil }
        if end == "timeout", g.timeControl == nil { return nil }
        var out: [String: Any] = [
            "id": g.id.uuidString.lowercased(), "engine": "zeist", "engine_version": String(g.engineVersion.prefix(24)),
            "level": level, "seed": seedSent(g).map { $0 as Any } ?? NSNull(), "side": g.player,
            "start": g.startFEN == GameModel.standardStart ? NSNull() : g.startFEN as Any,
            "moves": g.moves.joined(separator: " "), "result": result, "end": end,
            "app": "zeist-chess-ios", "rated": false,
        ]
        out["clock"] = g.timeControl.map { ["base": $0.base, "inc": $0.increment] as Any } ?? NSNull()
        return out
    }

    /// The engine's own Level (1 to 8) and Seed, as they were sent to it for this game.
    private static func option(_ g: GameRecord, _ name: String) -> String? {
        guard case .object(let s)? = g.engineSettings, case .array(let options)? = s["options"] else { return nil }
        for o in options {
            if case .array(let pair) = o, pair.count == 2, case .string(let k) = pair[0], k == name, case .string(let v) = pair[1] { return v }
        }
        return nil
    }
    static func engineLevel(_ g: GameRecord) -> Int? { option(g, "Level").flatMap { Int($0) } }
    static func seedSent(_ g: GameRecord) -> UInt32? { option(g, "Seed").flatMap { UInt32($0) } }

    // MARK: Whose game it is

    static let mark = "_by"
    enum Verdict: Equatable { case send, keep, drop }

    /// What to do with one waiting game. `by` is the account signed in when it was played (nil: nobody). A game played signed out goes on this iPhone's switch alone. A game played signed
    /// in goes only when that same account is signed in now and Zeist has just said its choice is yes; its no
    /// drops the game; anything else leaves it waiting.
    static func verdict(by: String?, session: Bool, owner: String?, archive: Bool?, fresh: Bool) -> Verdict {
        guard let by else { return .send }
        guard session else { return .keep }
        guard fresh, let owner, by == owner else { return .keep }
        switch archive { case true?: return .send; case false?: return .drop; case nil: return .keep }
    }

    /// A waiting game as it is sent: without the mark.
    static func sent(_ entry: [String: Any]) -> [String: Any] { entry.filter { $0.key != mark } }

    // MARK: The queue

    private static var file: URL { Places.support.appending(path: "shared-games.json") }
    private static func load() -> [[String: Any]] {
        guard let d = try? Data(contentsOf: file), let a = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return [] }
        return a
    }
    private static func save(_ q: [[String: Any]]) {
        if q.isEmpty { try? FileManager.default.removeItem(at: file); return }
        if let d = try? JSONSerialization.data(withJSONObject: q) { try? d.write(to: file, options: .atomic) }
    }

    /// A game has ended: if sharing is on and it was against the Zeist engine, it joins the queue and is sent.
    static func finished(_ g: GameRecord) {
        guard on, say != .never, var p = payload(g) else { return }
        // Played with a session held, the game waits under that account's name, so that only that account's own
        // yes can release it. The mark stays on this iPhone: it is never sent. A session Zeist hasn't named yet
        // has nobody to answer for the game, so the game isn't kept for sharing at all.
        if Account.shared.hasSession {
            guard let owner = Account.shared.owner else { return }
            p[mark] = owner
        }
        var q = load()
        if !q.contains(where: { $0["id"] as? String == p["id"] as? String }) { q.append(p) }
        save(Array(q.suffix(200)))
        Task { await flush() }
    }

    /// Turning sharing off forgets anything still waiting.
    /// Games waiting under an account that no longer exists can never be sent; they leave the queue.
    static func forget(owner: String) { save(load().filter { ($0[mark] as? String) != owner }) }

    static func apply() { if !on { save([]) } else { Task { await flush() } } }

    /// Sends what is waiting, up to twenty games. Games the server took, had already, or will never take leave the
    /// queue; anything else (no network, the day's limit reached) waits for another time.
    static func flush() async {
        guard on, !sending, !load().isEmpty else { return }
        sending = true
        defer { sending = false }
        // With a session held, Zeist is asked each time: a choice remembered from earlier isn't enough to send on.
        let session = Account.shared.hasSession
        let fresh = session ? await Account.shared.refresh() : true
        guard session == Account.shared.hasSession else { return }
        let owner = Account.shared.owner, archive = Account.shared.me?.chess_archive
        var q = load()
        let before = q.count
        q.removeAll { verdict(by: $0[mark] as? String, session: session, owner: owner, archive: archive, fresh: fresh) == .drop }
        if q.count != before { save(q) }
        let batch = q.filter { verdict(by: $0[mark] as? String, session: session, owner: owner, archive: archive, fresh: fresh) == .send }
            .prefix(20).map(sent)
        guard !batch.isEmpty, let body = try? JSONSerialization.data(withJSONObject: ["v": 1, "games": batch]) else { return }
        var req = URLRequest(url: address)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpShouldHandleCookies = false
        req.httpBody = body
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        guard let (data, response) = try? await URLSession(configuration: config).data(for: req),
              let http = response as? HTTPURLResponse else { return }
        let ids = Set(batch.compactMap { $0["id"] as? String })
        var drop = Set<String>()
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if http.statusCode == 200, let results = json?["results"] as? [[String: Any]] {
            for (i, r) in results.enumerated() where i < batch.count {
                let status = r["status"] as? String
                if status == "stored" || status == "duplicate" || (status == "refused" && r["reason"] as? String != "full") {
                    if let id = batch[i]["id"] as? String { drop.insert(id) }
                }
            }
        } else if (http.statusCode == 400 || http.statusCode == 413), json?["final"] as? Bool == true {
            drop = ids
        }
        guard !drop.isEmpty else { return }
        save(load().filter { !drop.contains($0["id"] as? String ?? "") })
    }
}
