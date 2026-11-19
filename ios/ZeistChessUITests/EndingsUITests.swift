import XCTest

/// Draw offers, the engine resigning, hints, a game from a position: through the real screens, against Stockfish Lite.
final class EndingsUITests: XCTestCase {
    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args + ["-play.pace", "NO", "-pick.side", "white"]
        app.launch()
        return app
    }

    /// Makes the first legal move found for the player's pieces.
    private func move(_ app: XCUIApplication, white: Bool = true) -> Bool {
        let mine = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'sq-' AND label CONTAINS %@", white ? "white" : "black"))
        for i in 0..<mine.count {
            let sq = mine.element(boundBy: i)
            sq.tap()
            let target = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'sq-' AND label CONTAINS 'legal move'")).firstMatch
            if target.waitForExistence(timeout: 1) { target.tap(); return true }
            sq.tap()
        }
        return false
    }

    private func wait(_ status: XCUIElement, _ text: String, _ timeout: Double = 30) -> Bool {
        let p = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: status)], timeout: timeout) == .completed
    }

    /// An engine never resigns: a hopeless game is played to checkmate.
    func testTheEngineNeverResigns() {
        let app = launch(["-reset", "-screen", "game", "-fen", "4k3/8/8/8/8/8/8/QR2K3 w - - 0 1"])
        let status = app.staticTexts["status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        for _ in 0..<6 {
            guard wait(status, "Your move", 20) else { break }
            XCTAssertTrue(move(app))
            sleep(1)
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'resigned'")).firstMatch.exists)
            if app.buttons["play-again"].exists { break }
        }
    }

    /// With human mode on, an engine that is badly beaten resigns.
    func testInHumanModeTheEngineResignsAHopelessGame() {
        let app = launch(["-reset", "-human", "-screen", "game", "-fen", "4k3/8/8/8/8/8/PPPPPPPP/RNBQKBNR w - - 0 1"])
        let status = app.staticTexts["status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        for _ in 0..<10 {
            if app.buttons["play-again"].exists { break }
            guard wait(status, "Your move", 20) else { break }
            XCTAssertTrue(move(app))
            sleep(1)
        }
        XCTAssertTrue(app.buttons["play-again"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["You won."].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Stockfish Lite resigned.'")).firstMatch.exists)
    }

    func testADrawOfferedEarlyIsDeclinedAndALevelOneIsAccepted() {
        var app = launch(["-reset", "-screen", "game"])
        var status = app.staticTexts["status"]
        XCTAssertTrue(wait(status, "Your move"))
        XCTAssertTrue(move(app))
        XCTAssertTrue(wait(status, "Your move"))
        app.buttons["game-menu"].tap()
        app.buttons["Offer a draw"].tap()
        XCTAssertTrue(wait(status, "declines the draw", 3))
        XCTAssertFalse(app.buttons["play-again"].exists)

        // A level ending, well past the opening.
        app = launch(["-reset", "-screen", "game", "-fen", "8/5pk1/6p1/8/8/6P1/5PK1/8 w - - 0 40"])
        status = app.staticTexts["status"]
        XCTAssertTrue(wait(status, "Your move"))
        XCTAssertTrue(move(app))
        XCTAssertTrue(wait(status, "Your move"))
        app.buttons["game-menu"].tap()
        app.buttons["Offer a draw"].tap()
        XCTAssertTrue(app.buttons["play-again"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["A draw."].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Draw agreed.'")).firstMatch.exists)
        // Rematch with colors swapped.
        app.buttons["rematch"].tap()
        sleep(3)
        XCTAssertTrue(app.descendants(matching: .any)["sq-a1"].label.contains("a1"))
        XCTAssertFalse(app.buttons["play-again"].exists)
    }

    func testAHintIsShownAndCounted() {
        let app = launch(["-reset", "-screen", "game"])
        let status = app.staticTexts["status"]
        XCTAssertTrue(wait(status, "Your move"))
        app.buttons["hint"].tap()
        let hinted = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'sq-' AND label CONTAINS 'hint: move this piece'")).firstMatch
        XCTAssertTrue(hinted.waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'hint: to here'")).firstMatch.exists)
    }

    func testAGameFromAPastedPGN() {
        let app = launch(["-reset"])
        XCTAssertTrue(app.buttons["picker"].waitForExistence(timeout: 10))
        app.buttons["picker"].tap()
        app.swipeUp(); app.swipeUp()
        XCTAssertTrue(app.buttons["from-position"].waitForExistence(timeout: 3))
        app.buttons["from-position"].tap()
        let field = app.textViews["position-text"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("nonsense")
        app.buttons["read"].tap()
        XCTAssertTrue(app.staticTexts["position-problem"].waitForExistence(timeout: 3))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "1. e4 c5 2. Nf3 d6 3. d4 cxd4")
        app.buttons["read"].tap()
        XCTAssertTrue(app.staticTexts["position-ply"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["position-ply"].label.contains("cxd4"))
        app.buttons["Back a move"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["position-ply"].label.contains("d4"))
        app.buttons["use-position"].tap()
        sleep(1)
        XCTAssertTrue(app.buttons["from-position"].label.contains("Your position") || app.staticTexts["Your position"].exists)
        app.buttons["Done"].tap()
        app.buttons["play"].tap()
        let status = app.staticTexts["status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        // Black to move after 3. d4: the player is Black and the engine (White) waits; Black moves first here.
        XCTAssertTrue(wait(status, "Your move"))
        XCTAssertTrue(app.descendants(matching: .any)["sq-d4"].label.contains("white pawn"))
    }
}
