import XCTest

final class ConsentUITests: XCTestCase {
    /// Where permission must be asked first, the line appears once on the first screen and an answer puts it away.
    func testTheConsentLineAsksOnceAndGoesWithAnAnswer() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-consent-ask"]
        app.launch()
        let no = app.buttons["consent-no"]
        XCTAssertTrue(no.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["May we count your visits?"].exists)
        XCTAssertTrue(app.buttons["consent-yes"].isHittable)
        if let path = ProcessInfo.processInfo.environment["CONSENT_SHOT"] {
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: path))
        }
        no.tap()
        XCTAssertTrue(no.waitForNonExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["-consent-ask"]
        app.launch()
        sleep(5)
        XCTAssertFalse(app.buttons["consent-no"].exists, "answered once, never asked again")
    }
}
