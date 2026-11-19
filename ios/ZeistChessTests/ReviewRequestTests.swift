import XCTest
@testable import ZeistChess

/// The rating request: who is ready, what a session rules out, and that a moment left behind is dropped.
@MainActor
final class ReviewRequestTests: XCTestCase {
    private let day = 86_400.0
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var now: Date { start.addingTimeInterval(10 * day) }

    /// A player who is ready: opened on four days, first open ten days ago, six finishes, never asked.
    private func ready() -> ReviewRequest.Saved {
        ReviewRequest.Saved(firstOpen: start, daysOpened: 4, lastDayOpened: "2027-01-20", finishedGames: 4, solvedPuzzles: 2)
    }
    private func ok(_ s: ReviewRequest.Saved, _ session: ReviewRequest.Session = .init(), version: String = "1.0") -> Bool {
        ReviewRequest.eligible(s, session: session, now: now, version: version)
    }

    func testAReadyPlayerMayBeAsked() {
        XCTAssertTrue(ok(ready()))
    }

    func testTooFewDaysOpened() {
        var s = ready(); s.daysOpened = ReviewRequest.minDaysOpened - 1
        XCTAssertFalse(ok(s))
    }

    func testTooSoonAfterTheFirstOpen() {
        var s = ready(); s.firstOpen = now.addingTimeInterval(-2.9 * day)
        XCTAssertFalse(ok(s))
        s.firstOpen = nil
        XCTAssertFalse(ok(s))
    }

    func testTooFewFinishes() {
        var s = ready(); s.finishedGames = 2; s.solvedPuzzles = 2
        XCTAssertFalse(ok(s))
        s.solvedPuzzles = 3
        XCTAssertTrue(ok(s))
    }

    func testTroubleInTheSessionRulesItOut() {
        XCTAssertFalse(ok(ready(), .init(trouble: true)))
    }

    func testOnlyOnceInASession() {
        XCTAssertFalse(ok(ready(), .init(asked: true)))
    }

    func testOnlyOnceForAVersion() {
        var s = ready(); s.lastRequestVersion = "1.0"; s.lastRequestDate = now.addingTimeInterval(-400 * day)
        XCTAssertFalse(ok(s))
        XCTAssertTrue(ok(s, version: "1.1"))
    }

    func testNotWithin120DaysOfTheLastRequest() {
        var s = ready(); s.lastRequestVersion = "0.9"; s.lastRequestDate = now.addingTimeInterval(-119 * day)
        XCTAssertFalse(ok(s))
        s.lastRequestDate = now.addingTimeInterval(-120 * day)
        XCTAssertTrue(ok(s))
    }

    func testTheDebugSwitchSkipsTheCountsButNotTheSession() {
        let s = ReviewRequest.Saved(force: true)
        XCTAssertTrue(ok(s))
        XCTAssertFalse(ok(s, .init(trouble: true)))
        XCTAssertFalse(ok(s, .init(asked: true)))
    }

    func testOpeningCountsEachDayOnce() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        var s = ReviewRequest.Saved()
        s = ReviewRequest.counted(.opened, in: s, now: start, calendar: cal)
        s = ReviewRequest.counted(.opened, in: s, now: start.addingTimeInterval(60), calendar: cal)
        XCTAssertEqual(s.daysOpened, 1)
        XCTAssertEqual(s.firstOpen, start)
        s = ReviewRequest.counted(.opened, in: s, now: start.addingTimeInterval(day), calendar: cal)
        s = ReviewRequest.counted(.opened, in: s, now: start.addingTimeInterval(3 * day), calendar: cal)
        XCTAssertEqual(s.daysOpened, 3)
        XCTAssertEqual(s.firstOpen, start)
        s = ReviewRequest.counted(.finishedGame, in: s, now: start)
        s = ReviewRequest.counted(.solvedPuzzle, in: s, now: start)
        XCTAssertEqual(s.finishes, 2)
    }

    // MARK: The type itself, with its own store and no StoreKit

    private func make(_ saved: ReviewRequest.Saved? = nil) -> (ReviewRequest, () -> [ReviewRequest.Moment], UserDefaults) {
        let name = "review-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        if let saved { d.set(try! JSONEncoder().encode(saved), forKey: ReviewRequest.key) }
        let at = now
        let r = ReviewRequest(defaults: d, version: "1.0", now: { at })
        r.wait = .zero
        var asked: [ReviewRequest.Moment] = []
        r.ask = { asked.append($0); return true }
        return (r, { asked }, d)
    }
    private func settle() async { for _ in 0..<5 { await Task.yield() }; try? await Task.sleep(for: .milliseconds(20)) }

    func testAGoodMomentAsksOnceAndRemembers() async {
        let (r, asked, d) = make(ready())
        r.considerAsking(after: .firstWinAtLevel)
        await settle()
        XCTAssertEqual(asked(), [.firstWinAtLevel])
        r.considerAsking(after: .puzzleMilestone)
        await settle()
        XCTAssertEqual(asked(), [.firstWinAtLevel], "never twice in a session")
        // The next launch, the same version: still no.
        let again = ReviewRequest(defaults: d, version: "1.0", now: { [now] in now })
        XCTAssertEqual(again.saved.lastRequestVersion, "1.0")
        XCTAssertFalse(ReviewRequest.eligible(again.saved, session: again.session, now: now, version: "1.0"))
    }

    func testNobodyIsAskedBeforeTheyAreReady() async {
        let (r, asked, _) = make()
        r.record(.opened)
        r.record(.finishedGame)
        r.considerAsking(after: .engineWin)
        await settle()
        XCTAssertEqual(asked(), [])
    }

    func testMovingOnDropsTheMoment() async {
        let (r, asked, _) = make(ready())
        r.considerAsking(after: .engineWin)
        r.movedOn()
        await settle()
        XCTAssertEqual(asked(), [])
        XCTAssertFalse(r.session.asked, "nothing was spent")
    }

    func testTroubleBeforeOrDuringTheWaitStopsIt() async {
        let (r, asked, _) = make(ready())
        r.considerAsking(after: .engineWin)
        r.record(.trouble)
        await settle()
        r.considerAsking(after: .engineWin)
        await settle()
        XCTAssertEqual(asked(), [])
    }

    func testARequestThatCouldNotBeMadeSpendsNothing() async {
        let (r, _, _) = make(ready())
        r.ask = { _ in false }
        r.considerAsking(after: .engineWin)
        await settle()
        XCTAssertFalse(r.session.asked)
        XCTAssertNil(r.saved.lastRequestVersion)
    }

    func testPuzzleMilestones() {
        var s = ready(); s.solvedPuzzles = 9
        let (r, _, _) = make(s)
        XCTAssertFalse(r.atPuzzleMilestone)
        r.record(.solvedPuzzle)
        XCTAssertTrue(r.atPuzzleMilestone)
        r.record(.solvedPuzzle)
        XCTAssertFalse(r.atPuzzleMilestone)
    }

    func testOnlyOneFileCallsStoreKit() throws {
        // The source is not in the test bundle; the rule is checked by `grep -rn requestReview ios/ZeistChess`.
        XCTAssertEqual(ReviewRequest.writeReview.absoluteString, "https://apps.apple.com/app/id6834922271?action=write-review")
    }
}
