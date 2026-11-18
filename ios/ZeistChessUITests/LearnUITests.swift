import XCTest

/// Learn, with the fixture lessons (ZeistChessTests/Fixtures/lessons, read by the app through -lessons): open a
/// lesson from its course, play a wrong move, use Hint, finish it, and find it marked finished on the course page.
final class LearnUITests: XCTestCase {
    /// The simulator reads the fixtures straight from the source folder.
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "ZeistChessTests/Fixtures/lessons").path

    func testPlayALessonThrough() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-lessons", Self.fixtures, "-pick.side", "white"]
        app.launch()
        let tab = app.tabBars.buttons["Learn"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        let course = Lesson.any(app, "course-checkmates")
        XCTAssertTrue(course.waitForExistence(timeout: 5))
        course.tap()
        Lesson.any(app, "lesson-checkmates-scholars-mate").tap()
        XCTAssertTrue(app.staticTexts["lesson-text"].waitForExistence(timeout: 5))

        // A show step: read, then Next.
        Lesson.next(app)
        XCTAssertTrue(Lesson.status(app, "White to move."))
        // A wrong move goes back with its line.
        Lesson.play(app, "d1h5")
        XCTAssertTrue(Lesson.status(app, "The queen aims at f7 too, but out this early she is easy to chase. Bring the bishop out first."))
        XCTAssertTrue(Lesson.square(app, "d1", has: "white queen"), "the queen went back")
        // Hint: the words, then the move.
        app.buttons["lesson-hint"].tap()
        XCTAssertTrue(Lesson.status(app, "The bishop on f1 can reach a square on the same diagonal as f7."))
        XCTAssertTrue(Lesson.square(app, "f1", has: "highlighted"), "the first tap lights the piece")
        app.buttons["lesson-hint"].tap()
        XCTAssertTrue(Lesson.square(app, "f1", has: "hint: move this piece"))
        Lesson.play(app, "f1c4")
        // The right move, its reply, then the next step by itself, the after line still under the board.
        XCTAssertTrue(Lesson.step(app, 3, of: 6))
        XCTAssertTrue(Lesson.status(app, "The bishop on c4 looks straight at f7."))
        XCTAssertTrue(Lesson.square(app, "c6", has: "black knight"), "the reply")
        // Back returns to the step as it was solved; Next goes on again.
        app.buttons["lesson-back"].tap()
        XCTAssertTrue(Lesson.step(app, 2, of: 6))
        XCTAssertTrue(Lesson.square(app, "c4", has: "white bishop"))
        Lesson.next(app)
        XCTAssertTrue(Lesson.step(app, 3, of: 6))

        Lesson.play(app, "d1h5")
        XCTAssertTrue(Lesson.step(app, 4, of: 6))
        Lesson.play(app, "h5f7")
        XCTAssertTrue(Lesson.step(app, 5, of: 6))
        XCTAssertTrue(Lesson.status(app, "Checkmate. The bishop guards the queen, and the king has no square."))
        Lesson.play(app, "g7g6")
        XCTAssertTrue(Lesson.step(app, 6, of: 6))
        // Next on a move not yet made plays it, and the end follows by itself.
        Lesson.next(app)

        XCTAssertTrue(app.staticTexts["lesson-finished"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["lesson-practice"].exists)
        XCTAssertFalse(app.buttons["lesson-next-lesson"].exists, "the last lesson of its course")
        app.buttons["lesson-course"].tap()
        let row = Lesson.any(app, "lesson-checkmates-scholars-mate")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.value as? String, "Finished")
    }
}

/// Driving a lesson through the board and the bar.
enum Lesson {
    static func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    static func play(_ app: XCUIApplication, _ uci: String) {
        any(app, "sq-\(uci.prefix(2))").tap()
        any(app, "sq-\(uci.dropFirst(2).prefix(2))").tap()
    }

    /// Taps Next once it can be pressed.
    static func next(_ app: XCUIApplication) {
        let b = app.buttons["lesson-next"]
        let on = NSPredicate(format: "isEnabled == true")
        _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: on, object: b)], timeout: 8)
        b.tap()
    }

    /// Drags the page up from an element (not from the board, which keeps its touches).
    static func scrollUp(_ app: XCUIApplication, from id: String) {
        let start = any(app, id).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)))
    }

    static func step(_ app: XCUIApplication, _ n: Int, of m: Int, timeout: Double = 10) -> Bool {
        let p = NSPredicate(format: "label == %@", "Step \(n) of \(m)")
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: any(app, "lesson-dots"))], timeout: timeout) == .completed
    }

    static func status(_ app: XCUIApplication, _ text: String, timeout: Double = 8) -> Bool {
        let p = NSPredicate(format: "label == %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: app.staticTexts["lesson-status"])], timeout: timeout) == .completed
    }

    static func square(_ app: XCUIApplication, _ sq: String, has text: String, timeout: Double = 8) -> Bool {
        let p = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: any(app, "sq-\(sq)"))], timeout: timeout) == .completed
    }
}
