import XCTest

/// Downloads an engine's network in Settings, picks it on Home, plays it, then deletes it in Settings. Its program is
/// in the app; only the network comes from the local pack server (ios/scripts/serve-packs.sh or packs-server.py).
final class DownloadUITests: XCTestCase {
    private static let server = "http://127.0.0.1:8799"

    private func serverIsUp() -> Bool {
        let done = expectation(description: "server")
        var up = false
        URLSession.shared.dataTask(with: URL(string: "\(Self.server)/koivisto/default.net")!) { _, r, _ in
            up = (r as? HTTPURLResponse)?.statusCode == 200; done.fulfill()
        }.resume()
        wait(for: [done], timeout: 20)
        return up
    }

    func testDownloadPlayAndDelete() throws {
        guard serverIsUp() else { throw XCTSkip("no pack server") }
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-packs", Self.server, "-play.pace", "NO", "-pick.side", "white"]
        app.launch()
        app.buttons["profile"].tap()
        let download = app.buttons["download-koivisto"]
        XCTAssertTrue(download.waitForExistence(timeout: 15))
        download.tap()
        let delete = app.buttons["delete-koivisto"]
        XCTAssertTrue(delete.waitForExistence(timeout: 120))
        app.buttons["Back"].firstMatch.tap()
        app.buttons["picker"].tap()
        let pick = app.buttons["pick-koivisto"]
        XCTAssertTrue(pick.waitForExistence(timeout: 5))
        pick.tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["picker"].label.contains("Koivisto"))
        app.buttons["play"].tap()
        let status = app.staticTexts["status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let your = NSPredicate(format: "label CONTAINS 'Your move'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: your, object: status)], timeout: 30), .completed)
        app.descendants(matching: .any)["sq-e2"].tap()
        app.descendants(matching: .any)["sq-e4"].tap()
        sleep(1)
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: your, object: status)], timeout: 30), .completed)
        // In a game without a clock, Resign is in the game's menu.
        app.buttons["game-menu"].tap()
        app.buttons["menu-resign"].tap()
        confirm(app, "Resign", not: "menu-resign")
        XCTAssertTrue(app.buttons["play-again"].waitForExistence(timeout: 5))
        app.buttons["end-home"].tap()
        XCTAssertTrue(app.buttons["profile"].waitForExistence(timeout: 5))
        app.buttons["profile"].tap()
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        confirm(app, "Delete", not: "delete-koivisto")
        XCTAssertTrue(app.buttons["download-koivisto"].waitForExistence(timeout: 5))
    }

    /// An engine with no data file plays straight away: no download, and nothing in Settings to delete.
    func testABuiltInEngineIsReadyWithNoDownload() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-reset", "-packs", "http://127.0.0.1:1", "-play.pace", "NO", "-pick.side", "white"]
        app.launch()
        app.buttons["picker"].tap()
        let pick = app.buttons["pick-ethereal"]
        XCTAssertTrue(pick.waitForExistence(timeout: 5))
        pick.tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["picker"].label.contains("Ethereal"))
        app.buttons["play"].tap()
        let status = app.staticTexts["status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let your = NSPredicate(format: "label CONTAINS 'Your move'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: your, object: status)], timeout: 30), .completed)
        app.descendants(matching: .any)["sq-e2"].tap()
        app.descendants(matching: .any)["sq-e4"].tap()
        sleep(1)
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: your, object: status)], timeout: 30), .completed)
        XCTAssertTrue(app.buttons["ply-2"].waitForExistence(timeout: 5), "the engine answered")
        app.buttons["game-menu"].tap()
        app.buttons["menu-resign"].tap()
        confirm(app, "Resign", not: "menu-resign")
        XCTAssertTrue(app.buttons["play-again"].waitForExistence(timeout: 5))
        app.buttons["end-home"].tap()
        app.buttons["profile"].tap()
        XCTAssertTrue(app.staticTexts["Ethereal"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["download-ethereal"].exists)
        XCTAssertFalse(app.buttons["delete-ethereal"].exists)
    }

    /// Taps a confirmation's button, not the button that opened it.
    private func confirm(_ app: XCUIApplication, _ label: String, not id: String) {
        let b = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", label, id)).firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: 5))
        b.tap()
    }
}
