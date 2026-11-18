import XCTest

/// Themes and the daily, through the screens: open Themes from Puzzles, open a theme and solve one of its puzzles;
/// open Today on a set date and solve the day's puzzle, then find the day counted.
final class PuzzleExtrasUITests: XCTestCase {
    func testSolveAPuzzleFromATheme() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-puzzle-answers", "-play.pace", "NO"]
        app.launch()
        let tab = app.tabBars.buttons["Puzzles"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        let themes = app.descendants(matching: .any)["puzzles-themes"]
        XCTAssertTrue(themes.waitForExistence(timeout: 5))
        themes.tap()
        let forks = app.descendants(matching: .any)["theme-forks"]
        XCTAssertTrue(forks.waitForExistence(timeout: 5))
        forks.tap()
        let top = app.descendants(matching: .any)["puzzle-top"]
        XCTAssertTrue(top.waitForExistence(timeout: 5))
        XCTAssertTrue(top.label.contains("Forks"), "the theme is named at the top: \(top.label)")
        XCTAssertTrue(PuzzleSolver.solve(app), "status: \(app.staticTexts["puzzle-status"].label)")
        let next = app.buttons["puzzle-next"]
        XCTAssertEqual(next.label, "Next puzzle")
        next.tap()
        XCTAssertTrue(PuzzleSolver.waitForMove(app), "Next stays inside the theme")
        XCTAssertTrue(top.label.contains("Forks"))
    }

    func testTodayOnASetDate() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-puzzle-answers", "-play.pace", "NO", "-today", "2026-11-20", "-daily-start", "2026-11-16", "-daily-solved", "2,3"]
        app.launch()
        let tab = app.tabBars.buttons["Puzzles"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        let today = app.descendants(matching: .any)["puzzles-today"]
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        XCTAssertTrue(today.label.contains("November 20"), today.label)
        XCTAssertTrue(today.label.contains("2 days in a row"), "yesterday and the day before: \(today.label)")
        today.tap()
        let top = app.descendants(matching: .any)["puzzle-top"]
        XCTAssertTrue(top.waitForExistence(timeout: 5))
        XCTAssertTrue(top.label.contains("Friday, November 20"), top.label)
        XCTAssertFalse(app.buttons["puzzle-next"].exists, "a day's puzzle has no Next")
        XCTAssertTrue(PuzzleSolver.solve(app), "status: \(app.staticTexts["puzzle-status"].label)")
        let count = app.staticTexts["daily-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertEqual(count.label, "3 days in a row")
        // A missed day is still playable from the calendar.
        Lesson.scrollUp(app, from: "daily-month")
        app.descendants(matching: .any)["daily-day-17"].tap()
        let p = NSPredicate(format: "label CONTAINS %@", "Tuesday, November 17")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: top)], timeout: 5), .completed)
        XCTAssertTrue(app.staticTexts["daily-note"].exists, "the line on how a missed day can still count")
    }

    /// No start in daily.json (simulated with -daily-start none), or today before the start: no Today entry at all.
    func testNoDailyWithoutAStart() throws {
        for args in [["-daily-start", "none"], ["-daily-start", "2026-11-16", "-today", "2026-11-15"]] {
            let app = XCUIApplication()
            app.launchArguments = ["-reset", "-screen", "puzzles"] + args
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["puzzles-themes"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.descendants(matching: .any)["puzzles-today"].exists, "no Today entry with \(args)")
        }
    }
}
