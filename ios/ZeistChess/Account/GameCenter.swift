import GameKit
import SwiftUI

/// Zeist Chess's Game Center achievements (ios/GameCenter/achievements.json): feats against the engines and in
/// puzzles. None rewards a streak, a daily visit or speed, and none names a level number.
/// What has been earned is kept on this iPhone and is the truth; Game Center mirrors it when the player is signed
/// in there. The app never asks anyone to sign in to Game Center.
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

@MainActor @Observable
final class GameCenter {
    static let shared = GameCenter()
    private let defaults = UserDefaults.standard
    private(set) var signedIn = false

    private var earned: Set<String> {
        get { Set(defaults.stringArray(forKey: "feats.earned") ?? []) }
        set { defaults.set(newValue.sorted(), forKey: "feats.earned") }
    }
    private func set(_ key: String) -> Set<String> { Set(defaults.stringArray(forKey: key) ?? []) }

    /// Listens for the player's Game Center sign-in. If they are not signed in, nothing is shown and nothing asked.
    func start() {
        #if DEBUG
        if NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.arguments.contains("-reset") { return }
        #endif
        GKLocalPlayer.local.authenticateHandler = { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.signedIn = GKLocalPlayer.local.isAuthenticated
                if self.signedIn { self.report(self.earned, banner: false) }
            }
        }
    }

    func gameEnded(_ g: GameRecord, strongest: Bool) {
        guard g.ending != "abandoned" else { return }
        var met = set("feats.met"), beaten = set("feats.beaten")
        if !g.fromPosition {
            met.insert(g.engineID)
            if g.outcome == "win" { beaten.insert(g.engineID) }
            defaults.set(met.sorted(), forKey: "feats.met")
            defaults.set(beaten.sorted(), forKey: "feats.beaten")
        }
        award(Feats.earned(by: g, strongest: strongest).union(Feats.shelf(met: met, beaten: beaten)))
    }

    /// solved: the puzzle was solved by the player (with or without a miss first), not shown.
    func puzzleDone(solved: Bool, firstTry: Bool, band: Int) {
        guard solved else { return }
        let n = defaults.integer(forKey: "feats.puzzles") + 1
        defaults.set(n, forKey: "feats.puzzles")
        award(Feats.puzzles(solved: n, hardFirstTry: firstTry && band == 8))
    }

    private func award(_ ids: Set<String>) {
        let fresh = ids.subtracting(earned)
        guard !fresh.isEmpty else { return }
        earned.formUnion(fresh)
        report(fresh, banner: true)
    }

    private func report(_ ids: Set<String>, banner: Bool) {
        guard signedIn, !ids.isEmpty else { return }
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
