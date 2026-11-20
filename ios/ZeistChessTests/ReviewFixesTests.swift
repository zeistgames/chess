import XCTest
@testable import ZeistChess

/// Fixes from the independent review of 2026-11-19: Game Center credit kept apart for each player, the consent
/// rule for usage measurement, and what Settings says about an engine's licenses and source.
@MainActor
final class ReviewFixesTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "review-fixes-tests"

    override func setUp() {
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    private func win(_ engine: String) -> GameRecord {
        var g = GameRecord(startFEN: GameModel.standardStart, fen: GameModel.standardStart, player: "w", engineID: engine, engineName: engine,
                           engineVersion: "1", packSHA: nil, level: 4, adaptive: true, rating: nil, engineSettings: nil, seed: 1, appVersion: "1.0")
        g.moves = ["e2e4", "e7e5"]
        g.result = "1-0"
        g.ending = "checkmate"
        return g
    }

    // MARK: Game Center

    func testASecondPlayerIsNeverGivenTheFirstPlayersFeats() {
        let l = FeatLedger(defaults)
        XCTAssertEqual(l.signedIn("A"), [])
        XCTAssertEqual(l.gameEnded(win("clover"), strongest: false, owner: "A"), ["zeistchess.first.clover"])
        for _ in 0..<9 { _ = l.puzzleSolved(firstTry: true, band: 3, owner: "A") }
        // B signs in on the same iPad: nothing of A's is theirs, and A's nine puzzles do not count toward B's ten.
        XCTAssertEqual(l.signedIn("B"), [])
        XCTAssertEqual(l.puzzleSolved(firstTry: true, band: 3, owner: "B"), [])
        XCTAssertEqual(l.set("earned", "B"), [])
        // A comes back to what was theirs, and their tenth puzzle earns the award.
        XCTAssertEqual(l.signedIn("A"), ["zeistchess.first.clover"])
        XCTAssertEqual(l.puzzleSolved(firstTry: true, band: 3, owner: "A"), ["zeistchess.puzzles.10"])
    }

    func testWhatWasEarnedSignedOutGoesToTheFirstPlayerOnly() {
        let l = FeatLedger(defaults)
        let d = FeatLedger.device
        XCTAssertEqual(l.gameEnded(win("clover"), strongest: false, owner: d), ["zeistchess.first.clover"])
        for _ in 0..<10 { _ = l.puzzleSolved(firstTry: false, band: 2, owner: d) }
        XCTAssertEqual(l.signedIn("A"), ["zeistchess.first.clover", "zeistchess.puzzles.10"])
        XCTAssertEqual(l.claimant, "A")
        XCTAssertEqual(l.set("earned", d), [], "the device's share has moved, not been copied")
        XCTAssertEqual(l.puzzles("A"), 10)
        // Later play with nobody signed in is the device's again; B is not given it, A is on return.
        XCTAssertEqual(l.gameEnded(win("halogen"), strongest: false, owner: d), ["zeistchess.first.halogen"])
        XCTAssertEqual(l.signedIn("B"), [])
        XCTAssertEqual(l.set("earned", d), ["zeistchess.first.halogen"])
        XCTAssertEqual(l.signedIn("A"), ["zeistchess.first.clover", "zeistchess.first.halogen", "zeistchess.puzzles.10"])
    }

    func testJoinedCountsEarnWhatTheyAddUpTo() {
        let l = FeatLedger(defaults)
        for _ in 0..<6 { _ = l.puzzleSolved(firstTry: false, band: 2, owner: FeatLedger.device) }
        XCTAssertEqual(l.signedIn("A"), [])
        for _ in 0..<3 { _ = l.puzzleSolved(firstTry: false, band: 2, owner: "A") }
        _ = l.puzzleSolved(firstTry: false, band: 2, owner: FeatLedger.device)
        XCTAssertEqual(l.signedIn("A"), ["zeistchess.puzzles.10"])
    }

    func testTheAccountsPuzzlesCountForItsGameCenterPlayer() {
        let l = FeatLedger(defaults)
        XCTAssertEqual(l.signedIn("A"), [])
        for _ in 0..<4 { _ = l.puzzleSolved(firstTry: false, band: 2, owner: "A") }
        // Signed in to Zeist: 60 solved there, some of them the four from here. The count is 60, not 64.
        XCTAssertEqual(l.accountSolved(60, account: "z1", owner: "A"), ["zeistchess.puzzles.10", "zeistchess.puzzles.50"])
        XCTAssertEqual(l.puzzles("A"), 60)
        // The same count again earns nothing, and a smaller one never takes anything back.
        XCTAssertEqual(l.accountSolved(60, account: "z1", owner: "A"), [])
        XCTAssertEqual(l.accountSolved(12, account: "z1", owner: "A"), [])
        XCTAssertEqual(l.puzzles("A"), 60)
        XCTAssertEqual(l.accountSolved(100, account: "z1", owner: "A"), ["zeistchess.puzzles.100"])
        // Another Game Center player beside the same Zeist account is not given its count; nor is the device.
        XCTAssertEqual(l.accountSolved(100, account: "z1", owner: "B"), [])
        XCTAssertEqual(l.puzzles("B"), 0)
        XCTAssertEqual(l.accountSolved(100, account: "z1", owner: FeatLedger.device), [])
        // B's own solves beside A's account are counted one by one, as with no account.
        XCTAssertFalse(l.counts(account: "z1", for: "B"))
        XCTAssertTrue(l.counts(account: "z1", for: "A"))
        for _ in 0..<9 { XCTAssertEqual(l.puzzleSolved(firstTry: false, band: 2, owner: "B"), []) }
        XCTAssertEqual(l.puzzleSolved(firstTry: false, band: 2, owner: "B"), ["zeistchess.puzzles.10"])
        // B's own Zeist account counts for B.
        XCTAssertEqual(l.accountSolved(50, account: "z2", owner: "B"), ["zeistchess.puzzles.50"])
        XCTAssertEqual(l.hardFirstTry(owner: "B"), ["zeistchess.puzzles.hard"])
        XCTAssertEqual(l.hardFirstTry(owner: "B"), [])
    }

    func testTheDeviceKeepsTheNamesItHadBeforePlayersWereKeptApart() {
        defaults.set(["zeistchess.first.clover"], forKey: "feats.earned")
        defaults.set(4, forKey: "feats.puzzles")
        let l = FeatLedger(defaults)
        XCTAssertEqual(l.set("earned", FeatLedger.device), ["zeistchess.first.clover"])
        XCTAssertEqual(l.puzzles(FeatLedger.device), 4)
    }

    // MARK: Consent

    func testWhereTheLawAsksFirstNothingIsMeasuredUntilYes() {
        for r in ["NL", "DE", "FR", "GB", "CH", "NO", "IS", "LI"] { XCTAssertTrue(Measure.mustAsk(region: r), r) }
        for r in ["US", "IN", "JP", "BR", "CA", "AU"] { XCTAssertFalse(Measure.mustAsk(region: r), r) }
        XCTAssertTrue(Measure.mustAsk(region: nil), "a device that names no region is asked")
        XCTAssertFalse(Measure.allowed(saved: nil, mustAsk: true))
        XCTAssertTrue(Measure.allowed(saved: nil, mustAsk: false))
        XCTAssertTrue(Measure.allowed(saved: true, mustAsk: true))
        XCTAssertFalse(Measure.allowed(saved: false, mustAsk: false))
    }

    // MARK: Engine notices

    private func manifest(_ id: String, license: String?, net: String?) -> Manifest {
        Manifest(id: id, name: id, version: "1", author: "Someone", license: license, net_license: net, source: "https://example.com/upstream",
                 line: nil, files: [], entry: "e.js", multipv: nil, total_bytes: nil, strength: nil)
    }

    func testAnEngineNamesBothLicensesAndItsOwnFolderAsSource() {
        XCTAssertEqual(manifest("stockfish-lite", license: "GPL-3.0-or-later", net: "CC0-1.0").licenses, "GPL-3.0-or-later. Network: CC0-1.0")
        XCTAssertEqual(manifest("arasan", license: "MIT", net: "MIT").licenses, "MIT")
        XCTAssertEqual(manifest("fairy-stockfish", license: "GPL-3.0-or-later", net: "none").licenses, "GPL-3.0-or-later")
        XCTAssertEqual(manifest("x", license: "A AND B", net: nil).licenses, "A, B")
        XCTAssertNil(manifest("x", license: nil, net: "MIT").licenses)
        XCTAssertEqual(manifest("fairy-stockfish", license: nil, net: nil).sourcePage.absoluteString,
                       "https://github.com/zeistgames/chess/tree/main/engines/fairy-stockfish")
    }
}
