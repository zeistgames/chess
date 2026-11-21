import XCTest

/// Rated games against the real Zeist, with a test account: run by hand, one game at a time, never in bulk.
/// Skipped unless LIVE_TOKEN (TEST_RUNNER_LIVE_TOKEN) holds the test account's session and LIVE_CASE names a case:
/// full (a whole game at level 1, your side played by Stockfish Lite), lose-start, lose-finish, flush.
/// RATED_SHOTS (a folder) keeps each end screen. Prints what the end card said, never the token.
final class RatedLiveUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    private func shot(_ name: String) {
        guard let dir = env["RATED_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appending(path: "\(name).png"))
    }

    private func launch(_ app: XCUIApplication, _ extra: [String], reset: Bool = true) throws {
        let token = try XCTUnwrap(env["LIVE_TOKEN"])
        app.launchArguments = (reset ? ["-reset"] : []) + ["-zeist-site", "https://zeist.gg", "-zeist-token", token] + extra
        app.launch()
    }

    private func startRated(_ app: XCUIApplication, level: Int?) {
        let picker = app.buttons["picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 20))
        sleep(3) // signed in by now
        picker.tap()
        app.buttons["pick-zeist"].tap()
        let rated = app.switches["rated-switch"]
        for _ in 0..<4 where !rated.isHittable { app.swipeUp() }
        if (rated.value as? String) != "1" { rated.switches.firstMatch.tap() }
        if let level {
            app.buttons["Level"].firstMatch.tap()
            app.buttons["Level \(level)"].tap()
        }
        for _ in 0..<4 where !app.buttons["Done"].isHittable { app.swipeUp() }
        app.buttons["Done"].tap()
        sleep(1)
        app.buttons["play"].tap()
    }

    private func endLine(_ app: XCUIApplication) -> String {
        for id in ["rated-change", "rated-first-ten", "rated-line"] {
            let e = app.descendants(matching: .any)[id]
            if e.exists { return "\(id): \(e.label)" }
        }
        return "no rated line"
    }

    private func resign(_ app: XCUIApplication) {
        let menu = app.buttons["game-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 30))
        menu.tap()
        app.buttons["menu-resign"].tap()
        app.buttons["Resign"].firstMatch.tap()
    }

    func testLive() throws {
        guard env["LIVE_TOKEN"] != nil, let which = env["LIVE_CASE"] else { throw XCTSkip("live checks run by hand") }
        let app = XCUIApplication()
        switch which {
        case "full", "promote":
            try launch(app, which == "promote" ? ["-autoplay", "-autoplay-promote"] : ["-autoplay"])
            startRated(app, level: 1)
            XCTAssertTrue(app.staticTexts["rated-game"].waitForExistence(timeout: 30), "the rated game began")
            XCTAssertTrue(app.buttons["play-again"].waitForExistence(timeout: 1200), "the game reached its end")
            sleep(6)
            print("LIVE full: \(app.staticTexts.matching(identifier: "status").firstMatch.label) | \(endLine(app))")
            shot("live-full")
        case "lose-start":
            try launch(app, ["-rated-lose", "start"])
            startRated(app, level: 2)
            sleep(4)
            XCTAssertFalse(app.staticTexts["rated-game"].exists, "the start's answer was lost: no game yet")
            app.buttons["play"].tap() // the same start again: Zeist answers with the game it made
            XCTAssertTrue(app.staticTexts["rated-game"].waitForExistence(timeout: 30))
            resign(app)
            XCTAssertTrue(app.buttons["play-again"].waitForExistence(timeout: 15))
            sleep(6)
            print("LIVE lose-start: \(endLine(app))")
            shot("live-lose-start")
        case "lose-finish":
            try launch(app, ["-rated-lose", "finish"])
            startRated(app, level: 2)
            resign(app)
            XCTAssertTrue(app.buttons["play-again"].waitForExistence(timeout: 15))
            sleep(4)
            print("LIVE lose-finish: \(endLine(app))")
            shot("live-lose-finish")
            // Back later: the kept finish goes again at launch, and Zeist says it has it.
            app.terminate()
            try launch(app, ["-screen", "settings"], reset: false)
            let row = app.buttons["your-rating"]
            XCTAssertTrue(row.waitForExistence(timeout: 20))
            sleep(5)
            row.tap()
            sleep(5)
            print("LIVE flush: rating row \(row.label)")
            shot("live-flush")
        default:
            XCTFail("unknown case \(which)")
        }
    }
}
