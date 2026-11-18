import XCTest

/// Learn as you play: a game started from Learn shows a card for what came up, the card opens its lesson, and the game
/// is there as it was on coming back; the same moves in a game from Play show nothing. The moves of both sides are
/// fed with -moves; -freeze keeps the engine from answering.
final class LearnPlayUITests: XCTestCase {
    /// Castling, in an opening with no chapter of its own (so the castling card is the first to come).
    static let castled = "g2g3,a7a6,g1f3,b7b6,f1g2,c7c6,e1g1"

    func testACardInAGameFromLearnOpensItsLesson() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-screen", "game", "-learn", "-moves", Self.castled, "-freeze"]
        app.launch()
        XCTAssertTrue(app.staticTexts["learn-game"].waitForExistence(timeout: 10), "marked as a game from Learn")
        let card = app.descendants(matching: .any)["play-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(card.label.contains("Castling"), card.label)
        card.tap()
        XCTAssertTrue(app.staticTexts["lesson-text"].waitForExistence(timeout: 10), "the lesson opens over the game")
        app.buttons["page-back"].tap()
        XCTAssertTrue(app.staticTexts["learn-game"].waitForExistence(timeout: 5), "back in the game")
        XCTAssertTrue(app.descendants(matching: .any)["sq-g1"].label.contains("white king"), "as it was")
        XCTAssertTrue(app.staticTexts["status"].exists, "the status line stays with a card up")
        // Put away, it does not come back.
        app.descendants(matching: .any)["play-card-close"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["play-card"].waitForExistence(timeout: 2))
    }

    func testTheSameMovesFromPlayShowNoCard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-screen", "game", "-moves", Self.castled, "-freeze"]
        app.launch()
        XCTAssertTrue(app.staticTexts["status"].waitForExistence(timeout: 10))
        sleep(3)
        XCTAssertFalse(app.descendants(matching: .any)["play-card"].exists)
        XCTAssertFalse(app.staticTexts["learn-game"].exists)
    }

    func testTheEntryOnLearnStartsAGame() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-screen", "learn"]
        app.launch()
        let play = app.buttons["learn-play"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        XCTAssertEqual(play.label, "Play")
        play.tap()
        XCTAssertTrue(app.staticTexts["learn-game"].waitForExistence(timeout: 15))
        app.buttons["Home"].firstMatch.tap()
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertEqual(play.label, "Continue", "a game from Learn in progress is picked up again here")
    }

    /// An opening the opponent's move reached waits until the player has replied.
    func testAnOpeningCardWaitsForThePlayersMove() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-screen", "game", "-learn", "-moves", "e2e4,c7c5", "-freeze"]
        app.launch()
        XCTAssertTrue(app.staticTexts["learn-game"].waitForExistence(timeout: 10))
        sleep(2)
        XCTAssertFalse(app.descendants(matching: .any)["play-card"].exists, "not while the player has a move to make")
        app.descendants(matching: .any)["sq-g1"].tap()
        app.descendants(matching: .any)["sq-f3"].tap()
        let card = app.descendants(matching: .any)["play-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(card.label.contains("Sicilian Defense"), card.label)
    }
}
