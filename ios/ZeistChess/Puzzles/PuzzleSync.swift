import Foundation
import Observation

/// Sharing puzzle progress and the daily puzzle with Zeist through the account, so one player has one record
/// wherever they solve: Zeist on the web, Chess in the Zeist app, and here. Zeist's docs/PUZZLE-PROGRESS.md is the
/// contract; the rules are PuzzleProgress's (outgoing, settle, merge, join).
///
/// Signed out, nothing is sent and everything stays on this iPhone. Signed in, one request sends what the account
/// has not taken (solves with the solver's moves, which Zeist checks and does not keep; puzzles seen; daily rows; the
/// step and the puzzle in hand) and brings back the account's own. Play never waits on it for more than a moment.
@MainActor @Observable
final class PuzzleSync {
    static let shared = PuzzleSync()

    /// Goes up whenever an answer changed what is kept, so a screen showing the record reads it again.
    private(set) var changes = 0

    /// The network: POST /api/chess/puzzles/progress with the session token, answering the body and the status.
    /// Replaced in tests, which never reach Zeist.
    var send: @MainActor (_ body: Data, _ token: String) async throws -> (Data, Int) = { body, token in
        var req = URLRequest(url: Account.base.appending(path: "/api/chess/puzzles/progress"), timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: req)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
    /// Who is signed in: the session token and the account's owner tag. Replaced in tests.
    var who: @MainActor () -> (token: String, owner: String)? = {
        guard let t = Keychain.token, let o = Account.shared.owner else { return nil }
        return (t, o)
    }

    private let defaults: UserDefaults
    private var running: Task<Bool, Never>?
    private var again = false
    private var waiting: Task<Void, Never>?
    /// The most requests one sync makes (each carries up to 100 items).
    static let maxRounds = 40

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private var off: Bool {
        #if DEBUG
        // Unit tests drive their own PuzzleSync; UI tests and -reset runs never reach Zeist.
        // A run against a test server named with -zeist-site (Hosts.swift) does sync.
        let args = ProcessInfo.processInfo.arguments
        if self === Self.shared, NSClassFromString("XCTestCase") != nil || (args.contains("-reset") && !args.contains("-zeist-site")) { return true }
        #endif
        return false
    }

    /// A moment after something changed (a puzzle finished), once for a burst of changes.
    func soon(after seconds: Double = 1.2) {
        guard !off, who() != nil else { return }
        waiting?.cancel()
        waiting = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    /// Opening puzzles: wait briefly for the account's answer before a puzzle is chosen, since another device may
    /// have moved on. Signed out or offline, nothing waits.
    func settleBriefly(_ seconds: Double = 2) async {
        guard !off, who() != nil else { return }
        let t = Task { await self.sync() }
        await withTaskGroup(of: Void.self) { g in
            g.addTask { _ = await t.value }
            g.addTask { try? await Task.sleep(for: .seconds(seconds)) }
            await g.next()
            g.cancelAll()
        }
    }

    /// Sends the whole queue and takes the account's answer. One runs at a time: a call during a run asks for one
    /// more pass and waits for it. Answers whether Zeist was reached and answered.
    @discardableResult
    func sync() async -> Bool {
        guard !off else { return false }
        if let r = running { again = true; return await r.value }
        let t = Task { () -> Bool in
            var ok = false
            repeat { self.again = false; ok = await self.rounds() } while self.again
            return ok
        }
        running = t
        let ok = await t.value
        running = nil
        return ok
    }

    private func rounds() async -> Bool {
        guard let me = who() else { return false }
        var skip = Set<String>()
        for _ in 0..<Self.maxRounds {
            let p = PuzzleProgress.load(defaults, owner: me.owner)
            let o = p.outgoing(skip: skip)
            let sent = p.clock ?? 0
            var body: [String: Any] = ["owner": me.owner, "since": p.since ?? 0, "clock": sent, "step": p.step,
                                       "current": p.current.map { ["id": $0.id, "missed": $0.missed] as [String: Any] } ?? NSNull()]
            body["solved"] = o.solved.map { ["id": $0.id, "moves": $0.moves] as [String: Any] }
            body["seen"] = o.seen
            if !o.daily.isEmpty { body["daily"] = o.daily.map { ["day": $0.day, "id": $0.row.id, "missed": $0.row.missed, "on": $0.row.on] as [String: Any] } }
            guard let json = try? JSONSerialization.data(withJSONObject: body),
                  let (data, status) = try? await send(json, me.token), status == 200, let a = PuzzleAnswer(data) else { return false }
            // The answer counts only for the account it was asked for.
            guard let now = who(), now.owner == me.owner, now.token == me.token else { return false }
            // Read again: a puzzle may have been finished while the request was out.
            var q = PuzzleProgress.load(defaults, owner: me.owner)
            let before = q
            q.settle(a, sent: o)
            q.merge(a, sent: sent)
            if q != before {
                q.save(defaults, owner: me.owner)
                changes += 1
            }
            var settled = 0, later = false
            // A refused solve is queued as seen and goes in the next request (settle), so it counts as settled.
            for r in a.results { if r.status == "later" { skip.insert(r.id); later = true } else { settled += 1 } }
            for r in a.dailyResults { if r.status == "unsolved" { skip.insert("day:\(r.day)") } else { settled += 1 } }
            // A day put aside as unsolved goes again in this sync once its puzzle is finished on the account (its
            // refused solve went as seen in a later request).
            let finished = Set(a.results.filter { $0.status == "solved" || $0.status == "seen" }.map(\.id))
            for (d, row) in q.out?.daily ?? [:] where finished.contains(row.id) && !a.dailyResults.contains(where: { String($0.day) == d }) { skip.remove("day:\(d)") }
            // Done when nothing is left to send. An answer that settles nothing of what was sent and puts nothing
            // off ends it too, so a broken answer can't loop; a request that carried nothing goes round again when
            // something was finished while it was out.
            if q.outgoing(skip: skip).isEmpty || (!o.isEmpty && settled == 0 && !later) { return true }
        }
        return true
    }
}
