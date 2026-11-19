import Foundation
import FirebaseAnalytics
import FirebaseCore

/// Usage measurement, through Google Analytics, to see how many people play, where, and with which engines.
/// What is sent: the events below with their few fields, and what Google's kit gathers on its own (app opens,
/// country from the network address, device model, iOS version). Never sent: the moves of a game, an account
/// name, or the advertising identifier (the kit is built without it).
/// Where the law asks for permission first (the EEA, the UK and Switzerland, by the device's region), nothing is
/// collected until the player says yes, asked once (Root's consent line), as in the main Zeist app. Everywhere else
/// it counts unless they say no. Either way the answer can be changed at any time in Settings.
/// A build without GoogleService-Info.plist (which is not in the repository) measures nothing and asks nothing.
@MainActor
enum Measure {
    static let key = "measure.on"
    private static var ready = false
    static let askRegions: Set<String> = Set("AT BE BG HR CY CZ DK EE FI FR DE GR HU IE IT LV LT LU MT NL PL PT RO SK SI ES SE IS LI NO GB CH".split(separator: " ").map(String.init))

    /// Whether a player in this region must be asked first. A device that names no region is asked.
    static func mustAsk(region: String?) -> Bool { region.map { askRegions.contains($0) } ?? true }
    /// Whether anything may be collected: a saved answer always wins; without one, only where nobody must be asked.
    static func allowed(saved: Bool?, mustAsk: Bool) -> Bool { saved ?? !mustAsk }

    static var mustAsk: Bool { mustAsk(region: Locale.current.region?.identifier) }
    private static var saved: Bool? { UserDefaults.standard.object(forKey: key) as? Bool }
    static var on: Bool { allowed(saved: saved, mustAsk: mustAsk) }
    /// Show the consent line: this build measures, the region asks first, and there is no answer yet.
    static var shouldAsk: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-consent-ask") { return saved == nil } // UI tests
        #endif
        return ready && mustAsk && saved == nil
    }

    static func start() {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-reset") || NSClassFromString("XCTestCase") != nil { return }
        #endif
        FirebaseApp.configure()
        ready = true
        apply()
    }

    /// The player's answer, from the consent line or the switch in Settings.
    static func answer(_ yes: Bool) {
        UserDefaults.standard.set(yes, forKey: key)
        apply()
    }

    private static func apply() {
        guard ready else { return }
        let ok = on
        Analytics.setAnalyticsCollectionEnabled(ok)
        Analytics.setConsent([.analyticsStorage: ok ? .granted : .denied, .adStorage: .denied, .adUserData: .denied, .adPersonalization: .denied])
    }

    static func gameStarted(engine: String, adaptive: Bool, rating: Bool, level: Int, clock: String?, side: String) {
        send("game_start", ["engine": engine, "difficulty": rating ? "rating" : adaptive ? "adaptive" : "level", "level": level,
                            "clock": clock ?? "none", "side": side])
    }

    static func gameEnded(engine: String, outcome: String, ending: String, plies: Int, level: Int, clock: String?) {
        send("game_end", ["engine": engine, "outcome": outcome, "ending": ending, "plies": plies, "level": level, "clock": clock ?? "none"])
    }

    static func puzzleDone(band: Int, result: String) { send("puzzle_done", ["band": band, "result": result]) }

    /// The app asked Apple to show its rating sheet after this moment. Apple decides whether the sheet appears, and
    /// nothing tells the app whether it did or what the player chose: this counts requests, not ratings given.
    static func reviewRequested(moment: String) { send("review_requested", ["moment": moment]) }

    static func engineInstalled(_ id: String) { send("engine_install", ["engine": id]) }

    private static func send(_ name: String, _ fields: [String: Any]) {
        guard ready, on else { return }
        Analytics.logEvent(name, parameters: fields)
    }
}
