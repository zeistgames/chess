import XCTest

/// A whole timed game against the bundled Stockfish Lite, through the real screens: a 1+1 clock chosen in the
/// picker, moves made by tapping, the increment seen on the clock, the engine's clock running while it thinks,
/// then the player's flag falling and the game ending as a loss on time, kept in Recent with its clock times.
final class TimedGameUITests: XCTestCase {
    func testABulletGamePlayedToItsEnd() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-play.pace", "NO", "-pick.side", "white"]
        app.launch()
        XCTAssertTrue(app.buttons["picker"].waitForExistence(timeout: 10))
        app.buttons["picker"].tap()
        let bullet = app.buttons["time-60+1"]
        if !bullet.waitForExistence(timeout: 3) || !bullet.isHittable { app.swipeUp() }
        XCTAssertTrue(bullet.waitForExistence(timeout: 3))
        bullet.tap()
        XCTAssertTrue(bullet.isSelected)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["picker"].label.contains("1+1"), app.buttons["picker"].label)
        app.buttons["play"].tap()

        let status = app.staticTexts["status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["undo"].exists, "timed games have no Undo")
        let mine = app.descendants(matching: .any)["clock-you"]
        let theirs = app.descendants(matching: .any)["clock-engine"]
        XCTAssertTrue(mine.waitForExistence(timeout: 5))
        XCTAssertEqual(seconds(mine), 60)

        let order = ["e2", "d2", "g1", "b1", "f1", "c1", "c2", "a2", "h2", "b2", "g2", "f2", "e1", "d1", "a1", "h1"]
        var gained = 0, moves = 0
        var engineSpent = false // the engine's clock moved off its start
        for n in 0..<6 {
            guard waitForYourMove(status) else { break }
            var moved = false
            for from in order {
                let sq = app.descendants(matching: .any)["sq-\(from)"]
                guard sq.label.contains("white") else { continue }
                sq.tap()
                let target = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'sq-' AND label CONTAINS 'legal move'")).firstMatch
                if target.waitForExistence(timeout: 1) {
                    let before = seconds(mine)
                    target.tap()
                    let after = seconds(mine)
                    // From the second move on, the increment is added: the clock reads at least what it did.
                    if n > 0, after >= before { gained += 1 }
                    moved = true
                    break
                }
                sq.tap()
            }
            XCTAssertTrue(moved, "No legal move found")
            moves += 1
            if seconds(theirs) != 60 { engineSpent = true }
        }
        XCTAssertGreaterThanOrEqual(moves, 4)
        XCTAssertGreaterThanOrEqual(gained, 3, "the increment shows on the clock after a move")
        XCTAssertTrue(waitForYourMove(status))
        if seconds(theirs) != 60 { engineSpent = true }
        XCTAssertTrue(engineSpent, "the engine's clock is pressed with each of its moves (it answers fast and gains its increment)")

        // Stop moving: the flag falls, and the game ends as a loss on time.
        let lost = NSPredicate(format: "label CONTAINS 'Your time ran out'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: lost, object: status)], timeout: 75), .completed, status.label)
        XCTAssertTrue(app.buttons["play-again"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Stockfish Lite won."].exists)
        XCTAssertEqual(seconds(mine), 0)

        // Recent keeps it, with the clocks.
        app.buttons["end-home"].tap()
        XCTAssertTrue(app.tabBars.buttons["Games"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Games"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Lost on time'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("1+1"), row.label)
        row.tap()
        XCTAssertTrue(app.staticTexts["replay-move"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Your clock'")).firstMatch.exists)
    }

    private func seconds(_ clock: XCUIElement) -> Int {
        // "2 minutes 58 seconds, running"
        let words = (clock.value as? String ?? "").replacingOccurrences(of: ",", with: "").split(separator: " ")
        var total = 0
        for (i, w) in words.enumerated() {
            guard let n = Int(w), i + 1 < words.count else { continue }
            total += words[i + 1].hasPrefix("minute") ? n * 60 : n
        }
        return total
    }

    private func waitForYourMove(_ status: XCUIElement) -> Bool {
        let p = NSPredicate(format: "label CONTAINS 'Your move'")
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: status)], timeout: 30) == .completed
    }
}
