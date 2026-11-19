import StoreKit
import UIKit

/// Asking for an App Store rating. Every request goes through here; nothing else calls StoreKit's review API.
///
/// Only Apple's own rating sheet is used, and Apple decides whether it appears (at most three times a year).
/// The app asks rarely and only just after something the player enjoyed: a win against an engine, a puzzle
/// milestone, a finished chapter or course. Never after a loss or a draw, never in a session that has shown an
/// error or an offline message, never twice in a session, and never until the player has plainly got something
/// from the app. What it remembers is a few counts and dates on this iPhone. Nothing is sent anywhere.
@MainActor
final class ReviewRequest {
    static let shared = ReviewRequest()

    // The thresholds. Starting values, kept together so an update can change them.
    static let minDaysOpened = 3
    static let minDaysSinceFirstOpen = 3
    static let minFinishes = 5
    static let minDaysBetweenRequests = 120
    /// The puzzles solved (in total) at which a request may be made.
    static let puzzleMilestones: Set<Int> = [10, 25, 50, 100, 250, 500, 1000]
    /// How long after the result is shown before asking, so the sheet never covers it.
    static let settle: Duration = .seconds(2)

    /// What is counted.
    enum Event {
        /// The app came to the front.
        case opened
        /// A game was played to its end (not abandoned), whatever the result.
        case finishedGame
        /// A puzzle was solved by the player, not shown.
        case solvedPuzzle
        /// A lesson was finished for the first time.
        case finishedLesson
        /// The app failed at something and said so: an error or an offline message was shown. Never a slip of the
        /// player's (a wrong move, a position that can't be read).
        case trouble
    }

    /// The good moments: the only places a request may come from.
    enum Moment: String {
        case engineWin = "engine_win"
        case firstWinAtLevel = "engine_win_first_at_level"
        case puzzleMilestone = "puzzle_milestone"
        case lessonChapter = "lesson_chapter"
        case lessonCourse = "lesson_course"
    }

    /// What is remembered between launches.
    struct Saved: Codable, Equatable {
        var firstOpen: Date?
        /// Different days the app was opened on, and the last of them ("2026-11-19", the device's calendar).
        var daysOpened = 0
        var lastDayOpened: String?
        var finishedGames = 0
        var solvedPuzzles = 0
        var finishedLessons = 0
        var lastRequestVersion: String?
        var lastRequestDate: Date?
        /// Debug builds: the next good moment asks, whatever the counts and dates say.
        var force = false

        var finishes: Int { finishedGames + solvedPuzzles + finishedLessons }
    }

    /// What is true of this run of the app only.
    struct Session: Equatable {
        var trouble = false
        var asked = false
    }

    /// Whether a good moment, having just happened, may ask. A pure function of what is remembered, this session,
    /// the date and the version.
    static func eligible(_ s: Saved, session: Session, now: Date, version: String) -> Bool {
        if session.trouble || session.asked { return false }
        if s.force { return true }
        guard let first = s.firstOpen else { return false }
        let day = 86_400.0
        if s.daysOpened < minDaysOpened { return false }
        if now.timeIntervalSince(first) < Double(minDaysSinceFirstOpen) * day { return false }
        if s.finishes < minFinishes { return false }
        if s.lastRequestVersion == version { return false }
        if let last = s.lastRequestDate, now.timeIntervalSince(last) < Double(minDaysBetweenRequests) * day { return false }
        return true
    }

    /// What an event does to what is remembered.
    static func counted(_ event: Event, in s: Saved, now: Date, calendar: Calendar = .current) -> Saved {
        var s = s
        switch event {
        case .opened:
            if s.firstOpen == nil { s.firstOpen = now }
            let c = calendar.dateComponents([.year, .month, .day], from: now)
            let day = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            if s.lastDayOpened != day { s.lastDayOpened = day; s.daysOpened += 1 }
        case .finishedGame: s.finishedGames += 1
        case .solvedPuzzle: s.solvedPuzzles += 1
        case .finishedLesson: s.finishedLessons += 1
        case .trouble: break
        }
        return s
    }

    static let key = "review.request"
    /// The version as the App Store names it ("1.0"), without the build number: one request for each.
    static var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    private let defaults: UserDefaults
    private let version: String
    private let now: @MainActor () -> Date
    /// Makes the request. Replaced in tests, which must never reach StoreKit.
    var ask: @MainActor (Moment) -> Bool = ReviewRequest.system
    /// The wait before asking (none in tests).
    var wait: Duration = ReviewRequest.settle

    private(set) var saved: Saved { didSet { if saved != oldValue { store() } } }
    private(set) var session = Session()
    /// The moment waiting for the screen to settle, and its number: moving on drops it.
    private var pending = 0
    private var waiting: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, version: String = ReviewRequest.appVersion, now: @escaping @MainActor () -> Date = { Date() }) {
        self.defaults = defaults
        self.version = version
        self.now = now
        saved = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) } ?? Saved()
    }

    private func store() {
        if let d = try? JSONEncoder().encode(saved) { defaults.set(d, forKey: Self.key) }
    }

    func record(_ event: Event) {
        if event == .trouble { session.trouble = true; movedOn(); return }
        saved = Self.counted(event, in: saved, now: now())
    }

    /// The puzzles solved so far are at a milestone (call after recording the solve).
    var atPuzzleMilestone: Bool { Self.puzzleMilestones.contains(saved.solvedPuzzles) }

    /// Called from the good moments. If the player is ready, waits for the screen to settle and then asks, unless
    /// they have moved on, the app has left the front, or trouble has shown since.
    /// shownIn: how long from now until the result is on the screen (a game's end card arrives after a pause).
    func considerAsking(after moment: Moment, shownIn: Duration = .zero) {
        guard Self.eligible(saved, session: session, now: now(), version: version) else { return }
        pending += 1
        let mine = pending
        waiting?.cancel()
        waiting = Task { [weak self] in
            guard let wait = self?.wait else { return }
            if wait > .zero { try? await Task.sleep(for: wait + shownIn) }
            guard let self, !Task.isCancelled, self.pending == mine,
                  Self.eligible(self.saved, session: self.session, now: self.now(), version: self.version) else { return }
            // Nothing is spent if the request could not be made (the app had left the front).
            guard self.ask(moment) else { return }
            self.session.asked = true
            self.saved.lastRequestVersion = self.version
            self.saved.lastRequestDate = self.now()
            self.saved.force = false
        }
    }

    /// The player went on to something else (another screen, the next puzzle, a new game): a moment still waiting is dropped.
    func movedOn() {
        pending += 1
        waiting?.cancel()
        waiting = nil
    }

    /// The App Store's page for writing a review (Settings, "Rate Zeist Chess").
    static let writeReview = URL(string: "https://apps.apple.com/app/id6834922271?action=write-review")!

    private static func system(_ moment: Moment) -> Bool {
        #if DEBUG
        if NSClassFromString("XCTestCase") != nil { return false }
        #endif
        guard UIApplication.shared.applicationState == .active,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) else { return false }
        // Something is over the screen the moment happened on (the share sheet, any other sheet): not now.
        if scene.windows.contains(where: { $0.isKeyWindow && $0.rootViewController?.presentedViewController != nil }) { return false }
        Measure.reviewRequested(moment: moment.rawValue)
        AppStore.requestReview(in: scene)
        return true
    }

    #if DEBUG
    /// Forgets everything and makes the next good moment ask (Settings in debug builds, and -review-now).
    func forceNext() {
        movedOn()
        session = Session()
        saved = Saved(force: true)
    }
    var forced: Bool { saved.force }
    #endif
}
