import XCTest

/// Opens Puzzles from the dock and solves the puzzle it shows, reading each expected move from the debug hook
/// (-puzzle-answers), then goes on to the next one.
final class PuzzleUITests: XCTestCase {
    func testSolveAPuzzleAndReachNext() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-puzzle-answers", "-play.pace", "NO", "-pick.side", "white"]
        app.launch()
        let tab = app.tabBars.buttons["Puzzles"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        XCTAssertTrue(app.staticTexts["Puzzles"].waitForExistence(timeout: 5))
        let turn = app.descendants(matching: .any)["puzzle-turn"]
        XCTAssertTrue(turn.waitForExistence(timeout: 10))
        let solved = PuzzleSolver.solve(app)
        XCTAssertTrue(solved, "status: \(app.staticTexts["puzzle-status"].label)")
        let next = app.buttons["puzzle-next"]
        XCTAssertTrue(next.isEnabled)
        XCTAssertEqual(next.label, "Next puzzle")
        next.tap()
        XCTAssertTrue(PuzzleSolver.waitForMove(app), "a puzzle follows")
        XCTAssertNotEqual(app.staticTexts["puzzle-status"].label, "Solved.")
    }
}

/// Plays the moves the line expects, one at a time, through the board.
enum PuzzleSolver {
    static func expected(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)["puzzle-expected"] }

    /// Waits until the line expects a move of the solver's.
    @discardableResult static func waitForMove(_ app: XCUIApplication, except other: String? = nil, timeout: Double = 10) -> Bool {
        let e = expected(app)
        guard e.waitForExistence(timeout: timeout) else { return false }
        let p = NSPredicate { obj, _ in
            guard let l = (obj as? XCUIElement)?.label else { return false }
            return l.count >= 4 && l != "none" && l != other
        }
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: e)], timeout: timeout) == .completed
    }

    static func play(_ app: XCUIApplication, _ uci: String) {
        app.descendants(matching: .any)["sq-\(uci.prefix(2))"].tap()
        app.descendants(matching: .any)["sq-\(uci.dropFirst(2).prefix(2))"].tap()
        if uci.count == 5 {
            let promote = app.buttons["promote-\(uci.suffix(1))"]
            if promote.waitForExistence(timeout: 2) { promote.tap() }
        }
    }

    /// Solves the puzzle on the screen. True when it reads "Solved."
    static func solve(_ app: XCUIApplication) -> Bool {
        let status = app.staticTexts["puzzle-status"]
        var last: String?
        for _ in 0..<8 {
            guard waitForMove(app, except: last) else { break }
            let m = expected(app).label
            play(app, m)
            last = m
            let done = NSPredicate(format: "label == 'Solved.'")
            if XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: done, object: status)], timeout: 3) == .completed { return true }
        }
        return status.label == "Solved."
    }
}
