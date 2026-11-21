import XCTest

/// Rated games, against the debug build's stand-in for Zeist (-rated-stub): never reaches Zeist.
/// With RATED_SHOTS set to a folder (TEST_RUNNER_RATED_SHOTS), each step's screen is kept there.
final class RatedUITests: XCTestCase {
    private var app: XCUIApplication!

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["RATED_SHOTS"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appending(path: "\(name).png"))
    }

    private func launch(_ stub: String) {
        app = XCUIApplication()
        app.launchArguments = ["-reset", "-rated-stub", stub, "-screen", "start"]
        app.launch()
    }

    /// Opens the sheet's Zeist engine with Rated on.
    private func ratedOn() {
        let zeist = app.buttons["pick-zeist"]
        XCTAssertTrue(zeist.waitForExistence(timeout: 15))
        zeist.tap()
        let rated = app.switches["rated-switch"]
        for _ in 0..<4 where !rated.isHittable { app.swipeUp() }
        XCTAssertTrue(rated.exists)
        shot("a1-zeist-rated-off")
        if (rated.value as? String) != "1" { rated.switches.firstMatch.tap() }
        XCTAssertTrue(app.staticTexts["rated-note"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["from-position"].exists, "a rated game starts from the usual position")
        XCTAssertFalse(app.buttons["time-none"].exists, "a rated game has no clock")
    }

    private func resignAndWait() {
        let menu = app.buttons["game-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15))
        menu.tap()
        XCTAssertFalse(app.buttons["offer-draw"].exists, "no draw offers in a rated game")
        shot("a7-menu")
        app.buttons["menu-resign"].tap()
        app.buttons["Resign"].firstMatch.tap()
        XCTAssertTrue(app.buttons["play-again"].waitForExistence(timeout: 10))
        sleep(2)
    }

    func testFirstTenGames() throws {
        launch("6,0")
        ratedOn()
        shot("a2-rated-on")
        app.buttons["Level"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Level 8"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Level 9"].exists, "Zeist has eight levels")
        shot("a3-level")
        app.buttons["Matched"].tap()
        app.swipeDown()
        let other = app.buttons["pick-stockfish-lite"].exists ? app.buttons["pick-stockfish-lite"] : app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pick-' AND identifier != 'pick-zeist'")).firstMatch
        other.tap()
        for _ in 0..<4 where !app.switches["rated-switch"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Rated games are against the Zeist engine."].exists)
        shot("a4-other-engine")
        app.swipeDown()
        app.buttons["pick-zeist"].tap()
        for _ in 0..<4 where !app.buttons["Done"].isHittable { app.swipeUp() }
        app.buttons["Done"].tap()
        sleep(2)
        XCTAssertTrue(app.buttons["picker"].label.contains("Rated"), app.buttons["picker"].label)
        shot("a5-home")
        app.buttons["play"].tap()
        XCTAssertTrue(app.staticTexts["rated-game"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["undo"].exists)
        XCTAssertFalse(app.buttons["hint"].exists)
        shot("a6-game")
        resignAndWait()
        XCTAssertTrue(app.staticTexts["rated-first-ten"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["rated-first-ten"].label, "7 of 10 rated games. Your rating shows after ten.")
        shot("a8-end")
    }

    func testRankedGamesAndTheRating() throws {
        launch("20,1482")
        ratedOn()
        XCTAssertTrue(app.staticTexts["rated-note"].label.contains("1482"), app.staticTexts["rated-note"].label)
        shot("b1-matched")
        for _ in 0..<4 where !app.buttons["Done"].isHittable { app.swipeUp() }
        app.buttons["Done"].tap()
        sleep(2)
        XCTAssertTrue(app.buttons["picker"].label.contains("Rated, 1482"), app.buttons["picker"].label)
        shot("b2-home")
        app.buttons["play"].tap()
        resignAndWait()
        let change = app.descendants(matching: .any)["rated-change"]
        XCTAssertTrue(change.waitForExistence(timeout: 5))
        XCTAssertEqual(change.label, "Your rating went from 1482 to 1496.")
        XCTAssertTrue(app.staticTexts["Your next rated game is against level 3."].exists)
        shot("b3-end")
        app.buttons["play-again"].tap()
        XCTAssertTrue(app.buttons["play-again"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["rated-game"].exists)
        shot("b4-again")
        resignAndWait()
        app.buttons["end-home"].tap()
        let profile = app.buttons["profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        profile.tap()
        let row = app.buttons["your-rating"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        sleep(1)
        shot("b5-settings")
        row.tap()
        XCTAssertTrue(app.staticTexts["rating-number"].waitForExistence(timeout: 10))
        sleep(1)
        XCTAssertEqual(app.staticTexts["rating-number"].label, "1510")
        shot("b6-rating")
        app.swipeUp()
        shot("b7-rating")
    }
}
