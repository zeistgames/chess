import GameKit
import SwiftUI

/// Zeist Chess's Game Center achievements (ios/GameCenter/achievements.json): feats against the engines and in
/// puzzles. None rewards a streak, a daily visit or speed, and none names a level number.
/// What has been earned is kept on this iPhone and is the truth (FeatLedger, apart for each Game Center player);
/// Game Center mirrors it when the player is signed in there. The app never asks anyone to sign in to Game Center.
@MainActor
enum Feats {
    static let engines = ["stockfish-lite", "stockfish", "fairy-stockfish", "maia", "arasan", "clover", "caissa", "plentychess",
                          "halogen", "koivisto", "ethereal", "zeist"]
    static let maia = [800, 1000, 1200, 1500, 1800, 2000, 2200]
    static let puzzleCounts = [10, 50, 100, 500, 1000]
    static let practiceEndings = Set(PositionSheet.setups.map(\.fen))

    /// What one finished game earns by itself. strongest: the engine was at its strongest setting.
    /// A game from a chosen position earns only "From an ending" (for the practice endings): winning a won
    /// position proves nothing about the engine.
    static func earned(by g: GameRecord, strongest: Bool) -> Set<String> {
        guard g.outcome == "win", g.ending != "abandoned" else { return [] }
        if g.fromPosition { return practiceEndings.contains(g.startFEN) ? ["zeistchess.feat.ending"] : [] }
        var out: Set<String> = []
        // The Zeist engine has none of its own here: beating it is rewarded in Zeist's Game Center.
        if engines.contains(g.engineID), g.engineID != "zeist" {
            // Game Center ids take no hyphens.
            let e = g.engineID.replacingOccurrences(of: "-", with: "_")
            out.insert("zeistchess.first.\(e)")
            if strongest { out.insert("zeistchess.best.\(e)") }
        }
        if g.engineID == "maia", let r = g.rating { for t in maia where r >= t { out.insert("zeistchess.maia.\(t)") } }
        if g.player == "b" { out.insert("zeistchess.feat.black") }
        if let c = g.timeClass, ["bullet", "blitz", "rapid"].contains(c) { out.insert("zeistchess.feat.\(c)") }
        // The player's own moves: every other one, starting with the first if they play White.
        let mine = g.moves.enumerated().filter { ($0.offset % 2 == 0) == (g.player == "w") }.map(\.element)
        if mine.contains(where: { $0.count == 5 && $0.hasSuffix("q") }) { out.insert("zeistchess.feat.queen") }
        if mine.contains(where: { $0.count == 5 && "nbr".contains($0.last!) }) { out.insert("zeistchess.feat.lesser") }
        if strongest, (g.hints ?? 0) == 0, g.undos == 0 { out.insert("zeistchess.feat.nohelp") }
        return out
    }

    /// What the whole record earns: every engine met, every engine beaten.
    static func shelf(met: Set<String>, beaten: Set<String>) -> Set<String> {
        var out: Set<String> = []
        if met.isSuperset(of: engines) { out.insert("zeistchess.shelf.met") }
        if beaten.isSuperset(of: engines) { out.insert("zeistchess.shelf.beaten") }
        return out
    }

    /// What a count of puzzles solved earns, and a hardest-band puzzle solved on the first try.
    static func puzzles(solved: Int, hardFirstTry: Bool) -> Set<String> {
        var out = Set(puzzleCounts.filter { solved >= $0 }.map { "zeistchess.puzzles.\($0)" })
        if hardFirstTry { out.insert("zeistchess.puzzles.hard") }
        return out
    }
}

/// What has been earned and counted, kept on this iPhone apart for each Game Center player, so one player's
/// feats are never sent under another's name on a shared iPad. With nobody signed in to Game Center it is kept
/// under the device itself. The first Game Center player this device sees takes the device's share, then and
/// whenever they come back; any other player starts from nothing and is never given it.
@MainActor
struct FeatLedger {
    static let device = "device"
    let defaults: UserDefaults
    init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// The device's own share keeps the names it had before players were kept apart.
    private func key(_ name: String, _ owner: String) -> String { owner == Self.device ? "feats.\(name)" : "feats.\(name).\(owner)" }
    func set(_ name: String, _ owner: String) -> Set<String> { Set(defaults.stringArray(forKey: key(name, owner)) ?? []) }
    func put(_ name: String, _ owner: String, _ v: Set<String>) { defaults.set(v.sorted(), forKey: key(name, owner)) }
    func puzzles(_ owner: String) -> Int { defaults.integer(forKey: key("puzzles", owner)) }
    func putPuzzles(_ owner: String, _ n: Int) { defaults.set(n, forKey: key("puzzles", owner)) }

    /// The Game Center player the device's share belongs to: the first one seen here.
    var claimant: String? { defaults.string(forKey: "feats.claimant") }

    /// A Game Center player is signed in. If the device's share is theirs it joins their own, with whatever the
    /// joined counts now earn. Answers everything this player has earned, to mirror to Game Center.
    func signedIn(_ player: String) -> Set<String> {
        if claimant == nil { defaults.set(player, forKey: "feats.claimant") }
        guard claimant == player else { return set("earned", player) }
        let d = Self.device
        var earned = set("earned", player).union(set("earned", d))
        let met = set("met", player).union(set("met", d)), beaten = set("beaten", player).union(set("beaten", d))
        let n = puzzles(player) + puzzles(d)
        earned.formUnion(Feats.shelf(met: met, beaten: beaten))
        earned.formUnion(Feats.puzzles(solved: n, hardFirstTry: false))
        put("earned", player, earned); put("met", player, met); put("beaten", player, beaten); putPuzzles(player, n)
        for name in ["earned", "met", "beaten", "puzzles"] { defaults.removeObject(forKey: key(name, d)) }
        return earned
    }

    /// A finished game, for this owner. Answers what it newly earned.
    func gameEnded(_ g: GameRecord, strongest: Bool, owner: String) -> Set<String> {
        guard g.ending != "abandoned" else { return [] }
        var met = set("met", owner), beaten = set("beaten", owner)
        if !g.fromPosition {
            met.insert(g.engineID)
            if g.outcome == "win" { beaten.insert(g.engineID) }
            put("met", owner, met); put("beaten", owner, beaten)
        }
        return award(Feats.earned(by: g, strongest: strongest).union(Feats.shelf(met: met, beaten: beaten)), owner)
    }

    /// A puzzle solved by this owner (with or without a miss first), not shown. Answers what it newly earned.
    func puzzleSolved(firstTry: Bool, band: Int, owner: String) -> Set<String> {
        let n = puzzles(owner) + 1
        putPuzzles(owner, n)
        return award(Feats.puzzles(solved: n, hardFirstTry: firstTry && band == 8), owner)
    }

    /// The puzzles solved in a Zeist account, wherever they were solved (Zeist on the web, the Zeist app, here):
    /// this player's count rises to it, never falls, and earns what it now adds up to. An account's count goes
    /// only to the first Game Center player it was signed in beside on this iPhone, so two people sharing an
    /// iPad and an account are not both given it. Answers what it newly earned.
    func accountSolved(_ n: Int, account: String, owner: String) -> Set<String> {
        guard owner != Self.device else { return [] }
        if defaults.string(forKey: "feats.account.\(account)") == nil { defaults.set(owner, forKey: "feats.account.\(account)") }
        guard counts(account: account, for: owner), n > puzzles(owner) else { return [] }
        putPuzzles(owner, n)
        return award(Feats.puzzles(solved: n, hardFirstTry: false), owner)
    }

    /// Whether this account's count is this player's: nobody has it yet, or they were the first beside it here.
    /// Any other player's puzzles are counted one by one on this iPhone, as with no account.
    func counts(account: String, for owner: String) -> Bool {
        guard owner != Self.device else { return false }
        let pair = defaults.string(forKey: "feats.account.\(account)")
        return pair == nil || pair == owner
    }

    /// A hardest-band puzzle solved on the first try. Answers it if newly earned.
    func hardFirstTry(owner: String) -> Set<String> { award(["zeistchess.puzzles.hard"], owner) }

    private func award(_ ids: Set<String>, _ owner: String) -> Set<String> {
        let had = set("earned", owner)
        let fresh = ids.subtracting(had)
        if !fresh.isEmpty { put("earned", owner, had.union(fresh)) }
        return fresh
    }
}

@MainActor @Observable
final class GameCenter {
    static let shared = GameCenter()
    private let ledger = FeatLedger()
    /// The Game Center player signed in now (Apple's id for them in this game), or nil.
    private var player: String?
    var signedIn: Bool { player != nil }
    /// The Zeist account signed in and the puzzles solved in its record, or nil with nobody signed in to Zeist.
    var account: @MainActor () -> (owner: String, solved: Int)? = {
        guard let o = Account.shared.owner else { return nil }
        return (o, PuzzleProgress.load(.standard, owner: o).done.values.filter { $0 == 1 }.count)
    }

    /// Listens for the player's Game Center sign-in. If they are not signed in, nothing is shown and nothing asked.
    /// Apple calls this again when the player signs out or another signs in.
    func start() {
        #if DEBUG
        if NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.arguments.contains("-reset") { return }
        #endif
        GKLocalPlayer.local.authenticateHandler = { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                let local = GKLocalPlayer.local
                self.player = local.isAuthenticated ? local.gamePlayerID : nil
                if let p = self.player {
                    self.report(self.ledger.signedIn(p), for: p, banner: false)
                    self.recount(banner: false)
                }
            }
        }
    }

    func gameEnded(_ g: GameRecord, strongest: Bool) {
        let fresh = ledger.gameEnded(g, strongest: strongest, owner: player ?? FeatLedger.device)
        if let p = player { report(fresh, for: p, banner: true) }
    }

    /// solved: the puzzle was solved by the player (with or without a miss first), not shown.
    /// Signed in to Zeist and to Game Center, the count is the account's (recount), so a puzzle solved in Zeist
    /// counts here and none counts twice. Otherwise it is counted on this iPhone.
    func puzzleDone(solved: Bool, firstTry: Bool, band: Int) {
        guard solved else { return }
        guard let p = player, let a = account(), ledger.counts(account: a.owner, for: p) else {
            let fresh = ledger.puzzleSolved(firstTry: firstTry, band: band, owner: player ?? FeatLedger.device)
            if let p = player { report(fresh, for: p, banner: true) }
            return
        }
        if firstTry, band == 8 { report(ledger.hardFirstTry(owner: p), for: p, banner: true) }
        recount()
    }

    /// The account's puzzle record changed or came into reach (a solve, an answer from Zeist, a sign-in): the
    /// Game Center player's count rises to it.
    func recount(banner: Bool = true) {
        guard let p = player, let a = account() else { return }
        report(ledger.accountSolved(a.solved, account: a.owner, owner: p), for: p, banner: banner)
    }

    /// Sends achievements to Game Center for the player who earned them, and only while that player is still the
    /// one signed in.
    private func report(_ ids: Set<String>, for owner: String, banner: Bool) {
        let local = GKLocalPlayer.local
        guard !ids.isEmpty, local.isAuthenticated, local.gamePlayerID == owner else { return }
        let list = ids.map { id -> GKAchievement in
            let a = GKAchievement(identifier: id)
            a.percentComplete = 100
            a.showsCompletionBanner = banner
            return a
        }
        GKAchievement.report(list) { _ in }
    }

    /// Opens Game Center's own list of achievements.
    func show() { GKAccessPoint.shared.trigger(state: .achievements) {} }
}
