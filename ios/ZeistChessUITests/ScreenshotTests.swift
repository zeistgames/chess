import XCTest

/// Screens for review, written to ios/screenshots when SCREENSHOTS_DIR is set (run on a simulator only).
/// Includes the worst cases: a very long engine name, a failed download, onboarding offline.
final class ScreenshotTests: XCTestCase {
    private var dir: URL? {
        ProcessInfo.processInfo.environment["SCREENSHOTS_DIR"].map { URL(fileURLWithPath: $0) }
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let png = app.screenshot().pngRepresentation
        if let dir { try? png.write(to: dir.appending(path: "\(name).png")) }
    }

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args + ["-play.pace", "NO", "-pick.side", "white"]
        app.launch()
        return app
    }

    /// Puzzles: a fresh one, after a miss, solved; one for White with a goal; and large text.
    func testPuzzleScreens() throws {
        try XCTSkipIf(dir == nil, "SCREENSHOTS_DIR not set")
        var app = launch(["-reset", "-screen", "puzzles", "-puzzle", "Gdz7L", "-puzzle-answers"])
        XCTAssertTrue(PuzzleSolver.waitForMove(app))
        sleep(1); shot(app, "40-puzzle-fresh")
        PuzzleSolver.play(app, "g7f6")
        XCTAssertTrue(app.buttons["puzzle-show"].waitForExistence(timeout: 5))
        sleep(1); shot(app, "41-puzzle-after-miss")
        XCTAssertEqual(app.staticTexts["puzzle-status"].label, "Not that one.")
        XCTAssertTrue(PuzzleSolver.solve(app))
        sleep(1); shot(app, "42-puzzle-solved")
        app = launch(["-reset", "-screen", "puzzles", "-puzzle", "RW8uC", "-puzzle-answers"])
        XCTAssertTrue(PuzzleSolver.waitForMove(app))
        sleep(1); shot(app, "43-puzzle-white-mate-in-one")
        app = launch(["-reset", "-screen", "puzzles", "-puzzle", "Gdz7L", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        sleep(3); shot(app, "44-puzzle-large-text")
    }

    /// Learn, with the lessons the app ships (core/lessons): Learn with a lesson in hand, the Basics course, Openings
    /// and an opening's page, a move step with marks, a pick step with its answers lit by Hint, the end of a lesson
    /// with practice and without; large text and the edge-to-edge board.
    func testLearnScreens() throws {
        try XCTSkipIf(dir == nil, "SCREENSHOTS_DIR not set")
        var app = launch(["-reset", "-lesson", "checkmates-scholars-mate", "-lesson-step", "1"])
        XCTAssertTrue(app.staticTexts["lesson-text"].waitForExistence(timeout: 10))
        sleep(2); shot(app, "50-lesson-move-marks")
        app.buttons["lesson-hint"].tap(); sleep(1); shot(app, "50b-lesson-hint-piece")
        app.buttons["lesson-hint"].tap(); sleep(1); shot(app, "50c-lesson-hint-move")
        app.buttons["page-back"].tap(); sleep(1); shot(app, "51-learn")
        XCTAssertTrue(Lesson.any(app, "learn-continue").exists)
        Lesson.any(app, "course-basics").tap(); sleep(1); shot(app, "52-course-basics")
        app.buttons["page-back"].tap(); sleep(1)
        Lesson.any(app, "course-openings").tap(); sleep(1); shot(app, "53-openings-white")
        if app.buttons["As Black"].exists { app.buttons["As Black"].tap(); sleep(1); shot(app, "53b-openings-black"); app.buttons["As White"].tap() }
        Lesson.any(app, "chapter-italian-game").tap(); sleep(3); shot(app, "54-opening-playing")
        sleep(5); shot(app, "54b-opening-at-rest")
        app = launch(["-lesson", "basics-king", "-lesson-step", "1"])
        XCTAssertTrue(app.staticTexts["lesson-text"].waitForExistence(timeout: 10))
        sleep(1); shot(app, "56-lesson-pick")
        app.buttons["lesson-hint"].tap(); sleep(1)
        if app.buttons["lesson-hint"].isEnabled { app.buttons["lesson-hint"].tap(); sleep(1) }
        shot(app, "56b-lesson-pick-hint")
        app = launch(["-lesson", "tactics-fork", "-lesson-step", "last"])
        XCTAssertTrue(app.staticTexts["lesson-text"].waitForExistence(timeout: 10))
        Lesson.next(app)
        XCTAssertTrue(app.staticTexts["lesson-finished"].waitForExistence(timeout: 8))
        sleep(1); shot(app, "55-lesson-end-practice")
        app = launch(["-lesson", "basics-pawn", "-lesson-step", "last"])
        XCTAssertTrue(app.staticTexts["lesson-text"].waitForExistence(timeout: 10))
        Lesson.next(app)
        XCTAssertTrue(app.staticTexts["lesson-finished"].waitForExistence(timeout: 5))
        sleep(1); shot(app, "57-lesson-end-no-practice")
        app = launch(["-lesson", "openings-sicilian-ideas", "-lesson-step", "2"])
        sleep(3); shot(app, "58-lesson-continuing-tint")
        app = launch(["-lesson", "openings-kings-indian-ideas", "-lesson-step", "last"])
        XCTAssertTrue(app.staticTexts["lesson-text"].waitForExistence(timeout: 10))
        Lesson.next(app)
        XCTAssertTrue(app.staticTexts["lesson-finished"].waitForExistence(timeout: 8))
        sleep(1); shot(app, "58b-lesson-end-black")
        app = launch(["-lesson", "checkmates-scholars-mate", "-lesson-step", "1", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        sleep(3); shot(app, "59-lesson-large-text")
        app = launch(["-edge", "-lesson", "tactics-fork", "-lesson-step", "1"])
        sleep(3); shot(app, "59b-lesson-edge")
        // Openings with the index's newer fields (for, plain groups, line, play), from the fixtures until the
        // shipped index has them.
        app = launch(["-reset", "-screen", "learn", "-lessons", LearnUITests.fixtures])
        Lesson.any(app, "course-openings").tap(); sleep(1); shot(app, "60-fixture-openings-white")
        app.buttons["As Black"].tap(); sleep(1); shot(app, "60b-fixture-openings-black")
        app.buttons["As White"].tap()
        Lesson.any(app, "chapter-italian-game").tap(); sleep(3); shot(app, "61-fixture-opening-playing")
        sleep(5); shot(app, "61b-fixture-opening-at-rest")
        app.buttons["opening-back"].tap(); app.buttons["opening-back"].tap(); sleep(1); shot(app, "61c-fixture-opening-stepped-back")
    }

    /// Puzzles with Today and Themes: the place (with a count, before the start, large text), Themes, a theme's
    /// puzzle, Today solved, Today after missed days, and the end of a lesson that offers its theme.
    func testPuzzleExtrasScreens() throws {
        try XCTSkipIf(dir == nil, "SCREENSHOTS_DIR not set")
        let daily = ["-daily-start", "2026-11-16"]
        var app = launch(["-reset", "-screen", "puzzles", "-today", "2026-11-20", "-daily-solved", "2,3"] + daily)
        XCTAssertTrue(app.descendants(matching: .any)["puzzles-today"].waitForExistence(timeout: 10))
        sleep(2); shot(app, "70-puzzles-place")
        app = launch(["-reset", "-screen", "puzzles", "-daily-start", "none"])
        sleep(3); shot(app, "70b-puzzles-no-daily")
        app = launch(["-reset", "-screen", "puzzles", "-today", "2026-11-20", "-daily-solved", "1,2,3", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"] + daily)
        sleep(3); shot(app, "70c-puzzles-large-text")
        app = launch(["-reset", "-screen", "puzzles", "-today", "2026-11-20", "-daily-solved", "1,2,3", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] + daily)
        sleep(3); shot(app, "70d-puzzles-largest-text")
        app = launch(["-reset", "-screen", "today", "-today", "2026-11-22", "-daily-solved", "1,2,3", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] + daily)
        sleep(3); shot(app, "73c-today-largest-text")
        app = launch(["-reset", "-screen", "themes"])
        sleep(4); shot(app, "71-themes")
        app.swipeUp(); sleep(1); shot(app, "71b-themes-more")
        app = launch(["-reset", "-puzzle-theme", "forks", "-puzzle-answers"])
        XCTAssertTrue(PuzzleSolver.waitForMove(app))
        sleep(1); shot(app, "72-theme-puzzle")
        app = launch(["-reset", "-screen", "today", "-today", "2026-11-20", "-daily-solved", "0,1,2,3", "-puzzle-answers"] + daily)
        XCTAssertTrue(PuzzleSolver.solve(app))
        sleep(1); shot(app, "73-today-solved")
        Lesson.scrollUp(app, from: "daily-month"); sleep(1); shot(app, "73b-today-solved-calendar")
        app = launch(["-reset", "-screen", "today", "-today", "2026-11-25", "-daily-solved", "0,1,2,4@8,6,7"] + daily)
        sleep(3); shot(app, "74-today-after-missed-days")
        Lesson.scrollUp(app, from: "daily-month"); sleep(1); shot(app, "74b-today-after-missed-days-calendar")
        app = launch(["-reset", "-lesson", "tactics-fork", "-lesson-step", "5"])
        XCTAssertTrue(app.staticTexts["lesson-text"].waitForExistence(timeout: 10))
        Lesson.next(app)
        XCTAssertTrue(app.staticTexts["lesson-finished"].waitForExistence(timeout: 8))
        sleep(1); shot(app, "75-lesson-end-puzzles")
    }

    /// Learn as you play: the entry on Learn, a card about the player's move, a card for an opening, and the end of a
    /// game from Learn with what came up in it.
    func testLearnPlayScreens() throws {
        try XCTSkipIf(dir == nil, "SCREENSHOTS_DIR not set")
        var app = launch(["-reset", "-screen", "learn"])
        XCTAssertTrue(app.buttons["learn-play"].waitForExistence(timeout: 10))
        sleep(2); shot(app, "80-learn-entry")
        let petrov = ["-moves", "e2e4,e7e5,g1f3,g8f6,f3e5,f6e4,d1e2,e4f6,e5c6,f8e7,c6d8,e8d8"]
        app = launch(["-reset", "-screen", "game", "-learn", "-freeze"] + petrov)
        XCTAssertTrue(untilCard(app, "discovered"))
        sleep(1); shot(app, "81-card-player-move")
        app = launch(["-reset", "-screen", "game", "-learn", "-freeze", "-moves", "e2e4,c7c5,g1f3"])
        XCTAssertTrue(Lesson.any(app, "play-card").waitForExistence(timeout: 10))
        sleep(2); shot(app, "82-card-opening")
        app = launch(["-reset", "-screen", "game", "-learn", "-moves",
                      "e2e4,c7c6,d2d4,d7d5,b1c3,d5e4,c3e4,g8f6,d1d3,e7e5,d4e5,d8a5,c1d2,a5e5,e1c1,f6e4,d3d8,e8d8,d2g5,d8c7,g5d8"])
        XCTAssertTrue(app.buttons["play-again"].waitForExistence(timeout: 15))
        sleep(2); shot(app, "83-end-what-came-up")
        app = launch(["-reset", "-screen", "game", "-learn", "-freeze", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"] + petrov)
        XCTAssertTrue(untilCard(app, "discovered"))
        sleep(1); shot(app, "84-card-large-text")
        app = launch(["-reset", "-screen", "game", "-learn", "-freeze", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] + petrov)
        XCTAssertTrue(untilCard(app, "discovered"))
        sleep(1); shot(app, "85-card-largest-text")
    }

    /// Puts cards away until one whose words contain `text` shows.
    private func untilCard(_ app: XCUIApplication, _ text: String) -> Bool {
        let card = Lesson.any(app, "play-card")
        for _ in 0..<8 {
            guard card.waitForExistence(timeout: 10) else { return false }
            if card.label.lowercased().contains(text) { return true }
            Lesson.any(app, "play-card-close").tap()
            sleep(1)
        }
        return false
    }

    func testScreens() throws {
        try XCTSkipIf(dir == nil, "SCREENSHOTS_DIR not set")

        // Onboarding.
        var app = launch(["-reset", "-onboarding"])
        XCTAssertTrue(app.buttons["next"].waitForExistence(timeout: 10))
        sleep(1); shot(app, "01-onboarding-hello")
        app.buttons["next"].tap(); sleep(1)
        app.buttons["level-3"].tap(); sleep(1); shot(app, "02-onboarding-level")
        app.buttons["next"].tap(); sleep(2)
        if app.buttons["choose-arasan"].exists { app.buttons["choose-arasan"].tap() }
        if app.buttons["choose-ethereal"].exists { app.buttons["choose-ethereal"].tap() }
        sleep(1); shot(app, "03-onboarding-engines")
        app.buttons["next"].tap(); sleep(1); shot(app, "04-onboarding-account")
        app.buttons["not-now"].tap(); sleep(1); shot(app, "05-home-setting-up")
        sleep(3); shot(app, "06-home")

        app.buttons["picker"].tap(); sleep(1); shot(app, "07-picker")
        app.buttons["Level"].firstMatch.tap(); sleep(1); shot(app, "08-picker-level")
        app.buttons["Rating"].firstMatch.tap(); sleep(1); shot(app, "08b-picker-rating")
        XCTAssertTrue(app.sliders["rating"].exists)
        app.buttons["Adaptive"].firstMatch.tap()
        app.buttons["Done"].tap()

        // A game.
        app = launch(["-reset", "-screen", "game", "-moves", "e2e4,e7e5,g1f3,b8c6,f1c4,g8f6,d2d3,f8c5,c2c3,d7d6", "-select", "f3"])
        sleep(4); shot(app, "09-game")
        app = launch(["-screen", "game", "-moves", "f2f3,e7e5,g2g4,d8h4"])
        sleep(4); shot(app, "10-game-end-loss")
        app = launch(["-screen", "game", "-moves", "d2d4,d7d5,c2c4"])
        sleep(4); app.terminate()
        app = launch([])
        XCTAssertEqual(app.buttons["play"].label, "Continue", "a game survives the app being ended")
        sleep(2); shot(app, "11-home-continue")
        app.tabBars.buttons["Games"].tap(); sleep(1); shot(app, "12-recent")
        app.tabBars.buttons["Play"].tap()

        // Settings, engines, the sign-in sheet.
        app.buttons["profile"].tap(); sleep(2); shot(app, "13-settings")
        app.buttons["sign-in"].tap(); sleep(1); shot(app, "14-sign-in-sheet")
        app.swipeDown(velocity: .fast); sleep(1)
        app.swipeUp(); sleep(1); shot(app, "15-settings-engines")
        app.swipeUp(); sleep(1); shot(app, "16-settings-engines-more")

        // Each board.
        for t in ["bone", "slate", "maple", "walnut"] {
            app = launch(["-theme", t, "-screen", "game", "-moves", "e2e4,c7c5,g1f3,d7d6,d2d4,c5d4,f3d4,g8f6,b1c3", "-select", "d4"])
            sleep(4); shot(app, "17-theme-\(t)")
        }

        // Each piece set, on two boards: the game (a selection, the last move) and a check.
        for set in ["zeist", "cburnett", "pirouetti"] {
            for t in ["bone", "walnut", "slate", "maple"] {
                app = launch(["-theme", t, "-pieces", set, "-screen", "game", "-moves", "e2e4,c7c5,g1f3,d7d6,d2d4,c5d4,f3d4,g8f6,b1c3", "-select", "d4"])
                sleep(4); shot(app, "18-pieces-\(set)-\(t)")
            }
            app = launch(["-theme", "bone", "-pieces", set, "-screen", "game", "-moves", "e2e4,e7e5,f2f4,d8h4"])
            sleep(4); shot(app, "18-pieces-\(set)-check")
        }
        app = launch(["-theme", "maple", "-pieces", "pirouetti", "-screen", "settings"])
        sleep(2); shot(app, "19-settings-pieces")
        app.buttons["pieces-pirouetti"].tap(); sleep(1); shot(app, "19-settings-pieces-chosen")
        XCTAssertTrue(app.buttons["pieces-pirouetti"].isSelected)
        app.swipeUp(); app.swipeUp(); app.swipeUp(); sleep(1); shot(app, "19-settings-credits")
        app.buttons["Back"].firstMatch.tap(); sleep(2); shot(app, "19-home-pieces")
        app = launch([])
        sleep(2); shot(app, "19-home-pieces-remembered")
        app.tabBars.buttons["Games"].tap(); sleep(1); shot(app, "19-recent-pieces")

        // The game screen: the line of moves, captures, clocks, stepping back, the end on time.
        let italian = "e2e4,e7e5,g1f3,b8c6,f1c4,g8f6,f3g5,d7d5,e4d5,f6d5,g5f7,e8f7,d1f3,f7e6,b1c3,c6b4,a2a3,b4c2,e1d1,c2a1"
        app = launch(["-reset", "-screen", "game", "-moves", italian])
        sleep(4); shot(app, "20-game-line-captures")
        XCTAssertTrue(app.buttons["ply-20"].exists)
        app.buttons["ply-17"].tap(); sleep(1); shot(app, "24-step-back")
        XCTAssertTrue(app.staticTexts["status"].label.contains("Tap the board to return"))
        app.buttons["step-back"].tap(); app.buttons["step-back"].tap(); sleep(1); shot(app, "24b-step-back-twice")
        app.descendants(matching: .any)["sq-e4"].tap(); sleep(1)
        XCTAssertFalse(app.staticTexts["status"].label.contains("Tap the board"), "one tap returns to the game")
        app.buttons["game-menu"].tap(); sleep(1); app.buttons["Flip the board"].firstMatch.tap(); sleep(1); shot(app, "29-flipped")

        app = launch(["-reset", "-screen", "game", "-time", "180+2", "-moves", italian, "-clock", "121.3,96.8"])
        sleep(4); shot(app, "21-timed-midway")
        XCTAssertTrue(app.descendants(matching: .any)["clock-you"].exists)
        XCTAssertFalse(app.buttons["undo"].exists)
        app = launch(["-reset", "-screen", "game", "-time", "60+0", "-moves", "e2e4,d7d5,e4d5,d8d5,b1c3,d5a5,d2d4,c7c6,g1f3,c8f5", "-clock", "9.6,41"])
        sleep(3); shot(app, "22-clock-under-ten")
        app = launch(["-reset", "-screen", "game", "-time", "60+0", "-moves", "e2e4,d7d5,e4d5,d8d5,b1c3,d5a5", "-clock", "1.2,38"])
        XCTAssertTrue(app.buttons["play-again"].waitForExistence(timeout: 12))
        sleep(1); shot(app, "23-flagged")
        app.buttons["See the board"].tap(); sleep(1); shot(app, "23b-flagged-board")
        // A flag against a bare king is a draw.
        app = launch(["-reset", "-screen", "game", "-time", "60+0", "-fen", "4k3/4p3/8/8/8/8/8/N3K3 w - - 0 1", "-moves", "a1b3", "-clock", "40,1.2", "-freeze"])
        XCTAssertTrue(app.buttons["play-again"].waitForExistence(timeout: 12))
        sleep(1); shot(app, "23c-flag-without-mating-material")
        // A premove waiting while the engine thinks.
        app = launch(["-reset", "-screen", "game", "-time", "180+0", "-moves", "e2e4,e7e5", "-player", "b", "-freeze", "-premove", "g8f6"])
        sleep(4); shot(app, "28-premove")
        app = launch(["-reset", "-edge", "-screen", "game", "-time", "300+3", "-moves", italian])
        sleep(4); shot(app, "26-edge-to-edge")
        app = launch(["-reset", "-screen", "start"])
        sleep(2); app.swipeUp(); sleep(1)
        if app.buttons["time-custom"].exists { app.buttons["time-custom"].tap() }
        sleep(1); shot(app, "25-time-picker")
        app = launch(["-reset", "-screen", "settings"])
        sleep(2); shot(app, "27-settings-board")
        app.buttons["Edge to edge"].firstMatch.tap(); sleep(1); shot(app, "27b-settings-edge")
        // Worst case: a long name, fifteen pieces taken, a clock under ten seconds.
        app = launch(["-reset", "-screen", "game", "-engine-name", "Stockfish Lite with a Very Long Name Indeed", "-time", "60+0",
                      "-fen", "4k3/8/8/8/8/8/PPPPPPPP/RNBQKBNR w KQ - 0 1", "-moves", "e2e4", "-clock", "55,7.3", "-freeze", "-standard-captures"])
        sleep(4); shot(app, "w4-long-name-fifteen-taken-low-clock")

        // Phase two: a position, openings, the menu, a hint, a declined draw, sharing from Recent, play settings.
        app = launch(["-reset", "-screen", "game", "-moves", "e2e4,c7c5,g1f3,d7d6,d2d4,c5d4,f3d4,g8f6,b1c3,a7a6"])
        sleep(5); shot(app, "30-game-opening-name")
        XCTAssertTrue(app.staticTexts["opening"].label.contains("Najdorf"), app.staticTexts["opening"].label)
        app.buttons["hint"].tap(); sleep(6); shot(app, "31-hint")
        app.buttons["game-menu"].tap(); sleep(1); shot(app, "32-game-menu")
        app.buttons["Offer a draw"].tap(); sleep(1); shot(app, "33-draw-declined")
        app = launch(["-reset"])
        XCTAssertTrue(app.buttons["picker"].waitForExistence(timeout: 10))
        app.buttons["picker"].tap(); sleep(1); app.swipeUp(); app.swipeUp(); sleep(1); shot(app, "34-picker-from-position")
        app.buttons["from-position"].tap(); sleep(1); shot(app, "35-position-sheet")
        app.buttons["The Lucena position"].tap(); sleep(1); shot(app, "35b-position-practice")
        app.textViews["position-text"].tap()
        app.textViews["position-text"].typeText("8/8/8/8/8/8/8/8 w - - 0 1")
        app.buttons["read"].tap(); sleep(1); shot(app, "35c-position-invalid")
        app.textViews["position-text"].tap()
        app.textViews["position-text"].typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30) + "1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7")
        app.buttons["read"].tap(); app.buttons["Back a move"].firstMatch.tap(); app.buttons["Back a move"].firstMatch.tap()
        sleep(1); shot(app, "35d-position-pgn-stepped")
        app.buttons["The Lucena position"].tap(); app.buttons["use-position"].tap(); sleep(1)
        app.buttons["Done"].tap(); sleep(2); shot(app, "36-home-from-position")
        app.buttons["play"].tap(); sleep(4); shot(app, "36b-game-from-position")
        app = launch(["-reset", "-screen", "game", "-time", "60+0", "-moves", "e2e4,d7d5,e4d5,d8d5,b1c3,d5a5", "-clock", "1.2,38"])
        XCTAssertTrue(app.buttons["play-again"].waitForExistence(timeout: 12))
        sleep(1); shot(app, "37-end-card-rematch-share")
        app.buttons["review"].tap(); sleep(2); shot(app, "38-recent-game-share")
        app = launch(["-reset", "-screen", "settings"])
        sleep(2); app.swipeUp(); app.swipeUp(); sleep(1); shot(app, "39-settings-play")

        // Worst cases.
        // A download that fails: the engine server can't be reached.
        app = launch(["-reset", "-packs", "http://127.0.0.1:1", "-screen", "settings"])
        let arasan = app.buttons["download-arasan"]
        XCTAssertTrue(arasan.waitForExistence(timeout: 10))
        app.swipeUp(); sleep(1)
        arasan.tap(); sleep(3); shot(app, "w1-failed-download")
        XCTAssertTrue(app.buttons["Retry"].exists)
        app = launch(["-reset", "-onboarding", "-packs", "http://127.0.0.1:1"])
        app.buttons["next"].tap(); sleep(1); app.buttons["next"].tap(); sleep(2); shot(app, "w3-onboarding-offline")
    }
}
