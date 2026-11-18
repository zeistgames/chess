import Foundation
import FirebaseAnalytics
import FirebaseCore

/// Usage measurement, through Google Analytics, to see how many people play, where, and with which engines.
/// What is sent: the events below with their few fields, and what Google's kit gathers on its own (app opens,
/// country from the network address, device model, iOS version). Never sent: the moves of a game, an account
/// name, or the advertising identifier (the kit is built without it). It can be turned off in Settings.
/// A build without GoogleService-Info.plist (which is not in the repository) measures nothing.
@MainActor
enum Measure {
    static let key = "measure.on"
    private static var ready = false

    static var on: Bool { UserDefaults.standard.object(forKey: key) == nil || UserDefaults.standard.bool(forKey: key) }

    static func start() {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-reset") || NSClassFromString("XCTestCase") != nil { return }
        #endif
        FirebaseApp.configure()
        ready = true
        apply()
    }

    /// Follows the switch in Settings.
    static func apply() {
        guard ready else { return }
        Analytics.setAnalyticsCollectionEnabled(on)
    }

    static func gameStarted(engine: String, adaptive: Bool, rating: Bool, level: Int, clock: String?, side: String) {
        send("game_start", ["engine": engine, "difficulty": rating ? "rating" : adaptive ? "adaptive" : "level", "level": level,
                            "clock": clock ?? "none", "side": side])
    }

    static func gameEnded(engine: String, outcome: String, ending: String, plies: Int, level: Int, clock: String?) {
        send("game_end", ["engine": engine, "outcome": outcome, "ending": ending, "plies": plies, "level": level, "clock": clock ?? "none"])
    }

    static func puzzleDone(band: Int, result: String) { send("puzzle_done", ["band": band, "result": result]) }

    static func engineInstalled(_ id: String) { send("engine_install", ["engine": id]) }

    private static func send(_ name: String, _ fields: [String: Any]) {
        guard ready, on else { return }
        Analytics.logEvent(name, parameters: fields)
    }
}
