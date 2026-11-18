import XCTest

/// Plays several full moves against the bundled Stockfish Lite, through the real screens.
final class PlayUITests: XCTestCase {
    func testPlaySeveralMovesAgainstStockfishLite() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-play.pace", "NO", "-pick.side", "white"]
        app.launch()
        let play = app.buttons["play"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        XCTAssertEqual(play.label, "Play")
        play.tap()
        let status = app.staticTexts["status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let order = ["e2", "d2", "g1", "b1", "f1", "c1", "c2", "a2", "h2", "b2", "g2", "f2", "e1", "d1", "a1", "h1"]
        var played = 0
        for _ in 0..<6 {
            XCTAssertTrue(waitForYourMove(status), "Expected your move, status: \(status.label)")
            var moved = false
            for from in order {
                let sq = app.descendants(matching: .any)["sq-\(from)"]
                guard sq.label.contains("white") else { continue }
                sq.tap()
                let target = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'sq-' AND label CONTAINS 'legal move'")).firstMatch
                if target.waitForExistence(timeout: 1) { target.tap(); moved = true; break }
                sq.tap()
            }
            XCTAssertTrue(moved, "No legal move found")
            played += 1
        }
        XCTAssertTrue(waitForYourMove(status))
        XCTAssertGreaterThanOrEqual(played, 6)
        // Home now offers the game in progress.
        app.buttons["Home"].firstMatch.tap()
        XCTAssertTrue(app.buttons["play"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["play"].label, "Continue")
    }

    private func waitForYourMove(_ status: XCUIElement) -> Bool {
        let p = NSPredicate(format: "label CONTAINS 'Your move'")
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: status)], timeout: 30) == .completed
    }
}
