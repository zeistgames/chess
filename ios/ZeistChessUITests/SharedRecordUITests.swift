import XCTest

/// The app's half of the two-way check of the shared puzzle record: Zeist Chess against a Zeist test server, with the
/// website on the same server as the other client. Skipped unless a run names the server:
///   TEST_RUNNER_GATE_SITE=https://localhost:8794 [TEST_RUNNER_GATE_TOKEN=<session>] [TEST_RUNNER_GATE_RESET=1]
///   [TEST_RUNNER_GATE_OUT=<file for what was seen>] [TEST_RUNNER_GATE_PUZZLE=<id> TEST_RUNNER_GATE_WRONG=<uci>]
/// Each test is one step; whoever runs them reads the server's rows and the website in between.
final class SharedRecordUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var seen: [String] = []

    private func launch(_ extra: [String] = []) throws -> XCUIApplication {
        guard let site = env["GATE_SITE"] else { throw XCTSkip("no test server named") }
        let app = XCUIApplication()
        var args = ["-zeist-site", site, "-puzzle-answers", "-play.pace", "NO", "-daily-start", "2026-11-16"]
        if env["GATE_RESET"] == "1" { args.insert("-reset", at: 0) }
        if let t = env["GATE_TOKEN"] { args += ["-zeist-token", t] }
        app.launchArguments = args + extra
        app.launch()
        return app
    }

    private func note(_ s: String) { seen.append(s) }
    override func tearDown() {
        if let out = env["GATE_OUT"] { try? seen.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8) }
    }

    private func openPuzzles(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["Puzzles"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15))
        tab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["puzzle-turn"].waitForExistence(timeout: 15))
    }

    private func label(_ app: XCUIApplication, _ id: String) -> String {
        let e = app.descendants(matching: .any)[id].firstMatch
        return e.exists ? e.label : "(none)"
    }

    /// Solves the puzzle the Puzzles place offers, and waits for it to be sent.
    func testSolveOne() throws {
        let app = try launch()
        openPuzzles(app)
        XCTAssertTrue(PuzzleSolver.solve(app), "status: \(label(app, "puzzle-status"))")
        sleep(6)
        note("status=\(label(app, "puzzle-status"))")
    }

    /// Solves two in a row.
    func testSolveTwo() throws {
        let app = try launch()
        openPuzzles(app)
        XCTAssertTrue(PuzzleSolver.solve(app))
        app.buttons["puzzle-next"].tap()
        XCTAssertTrue(PuzzleSolver.waitForMove(app))
        XCTAssertTrue(PuzzleSolver.solve(app))
        sleep(6)
    }

    /// Opens Puzzles and waits, so the account's progress arrives; says what Today's entry reads.
    func testOpenAndWait() throws {
        let app = try launch()
        openPuzzles(app)
        sleep(7)
        note("today=\(label(app, "puzzles-today"))")
        note("status=\(label(app, "puzzle-status"))")
    }

    /// Opens today's daily: says what it reads before anything is played, then solves it and says what it reads after.
    func testDaily() throws {
        let app = try launch()
        openPuzzles(app)
        sleep(4)
        note("today-before=\(label(app, "puzzles-today"))")
        app.descendants(matching: .any)["puzzles-today"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["puzzle-top"].waitForExistence(timeout: 10))
        sleep(3)
        note("count-before=\(label(app, "daily-count"))")
        XCTAssertTrue(PuzzleSolver.solve(app), "status: \(label(app, "puzzle-status"))")
        sleep(6)
        note("count-after=\(label(app, "daily-count"))")
        note("status=\(label(app, "puzzle-status"))")
    }

    /// A wrong move, Show the move, then at once Retry and the solve.
    func testShowThenRetryAndSolve() throws {
        guard let id = env["GATE_PUZZLE"], let wrong = env["GATE_WRONG"] else { throw XCTSkip("no puzzle named") }
        let app = try launch(["-puzzle", id])
        openPuzzles(app)
        XCTAssertTrue(PuzzleSolver.waitForMove(app))
        PuzzleSolver.play(app, wrong)
        let show = app.buttons["puzzle-show"]
        XCTAssertTrue(show.waitForExistence(timeout: 5))
        let ready = NSPredicate(format: "isEnabled == true")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: ready, object: show)], timeout: 5), .completed)
        show.tap()
        let retry = app.buttons["puzzle-retry"]
        let line = NSPredicate(format: "label == 'That was the line.'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: line, object: app.staticTexts["puzzle-status"])], timeout: 15), .completed)
        // Retry, until the board is back at its start (the line has gone from under it).
        for _ in 0..<4 where label(app, "puzzle-status") == "That was the line." {
            if retry.exists, retry.isEnabled { retry.tap() }
            usleep(600_000)
        }
        note("after-retry=\(label(app, "puzzle-status"))")
        XCTAssertTrue(PuzzleSolver.solve(app), "status: \(label(app, "puzzle-status"))")
        sleep(7)
        note("status=\(label(app, "puzzle-status"))")
    }
}
