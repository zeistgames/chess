import SwiftUI

/// Puzzles: a puzzle straight away, not a menu. Under the title, two quiet entries, Today and Themes; then whose move
/// it is, the board, a quiet line, and the puzzle's controls as plain parts of the page (the dock is the one bar at
/// the bottom of this screen). Unrated: no timer, no score; the only count is Today's days in a row.
struct PuzzleScreen: View {
    @Binding var path: [Route]
    @State private var model = PuzzleScreen.shared
    @State private var today = PuzzleToday.read()
    @Environment(\.horizontalSizeClass) private var size
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var typeSize

    /// One puzzle in hand for the whole launch, so switching places in the dock keeps it.
    @MainActor static let shared = PuzzleModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            entries.padding(.horizontal, 20).padding(.top, 10)
            Spacer(minLength: 8)
            PuzzleBoardArea(model: model).frame(maxWidth: 720)
            PuzzlePlainControls(model: model)
                .padding(.horizontal, size == .regular ? 40 : 16).padding(.top, 10).padding(.bottom, 8)
                .frame(maxWidth: 720)
            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Z.ground.ignoresSafeArea())
        .foregroundStyle(Z.ink)
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.start() }
        .onAppear { Feel.shared.prepare(); shown() }
        .onChange(of: path) { _, p in if p.isEmpty { shown() } }
        // The account's answer may bring a day or a puzzle finished on another device.
        .onChange(of: PuzzleSync.shared.changes) { _, _ in shown() }
        // Today follows the date: midnight, a change of time zone, coming back to the app.
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in today = PuzzleToday.read() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in today = PuzzleToday.read() }
        .onChange(of: phase) { _, p in if p == .active { today = PuzzleToday.read() } }
    }

    /// Back in view: Today read again, and a puzzle solved meanwhile on another screen is not offered again.
    private func shown() {
        today = PuzzleToday.read()
        Task { await model.moveOnIfDoneElsewhere() }
    }

    private var header: some View {
        HStack {
            Text("Puzzles").font(Z.title(32, relativeTo: .title)).accessibilityAddTraits(.isHeader)
            Spacer()
            ProfileButton()
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    /// Side by side, one row (Today shortens its words to fit); one above the other only at accessibility text sizes.
    @ViewBuilder private var entries: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                todayEntry
                themesEntry
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 10) {
                todayEntry
                themesEntry.layoutPriority(1)
                Spacer(minLength: 0)
            }
        }
    }

    private var todayEntry: some View {
        TodayEntry(today: today) { if let d = today.day, d >= 0 { path.append(.today(d)) } }
    }

    private var themesEntry: some View {
        Entry(symbol: "square.grid.2x2", title: "Themes", detail: nil, check: false) { path.append(.themes) }
            .accessibilityIdentifier("puzzles-themes")
    }
}

/// What the Today entry shows: today's day number (nil without a daily list), the days in a row, and whether today
/// is solved. Read from the saved progress each time Puzzles shows.
struct PuzzleToday: Equatable {
    var day: Int?
    var start: String?
    var count = 0
    var solved = false

    @MainActor static func read(set: PuzzleSet = .shared, defaults: UserDefaults = .standard) -> PuzzleToday {
        guard let d = DailyCalendar.today(of: set.daily), let start = DailyCalendar.start(of: set.daily) else { return PuzzleToday() }
        let p = PuzzleProgress.load(defaults)
        return PuzzleToday(day: d, start: start, count: DailyStreak.count(today: d, solvedOn: p.dailySolvedOn), solved: p.daily?[String(d)] != nil)
    }

    static func inARow(_ n: Int) -> String { n == 1 ? "1 day in a row" : "\(n) days in a row" }
}

/// Today's entry: the date and, when there is one, the count; a quiet check once today is solved. With no daily
/// (no start yet, or before it) there is no entry at all.
struct TodayEntry: View {
    let today: PuzzleToday
    let action: () -> Void

    var body: some View {
        if let d = today.day, let start = today.start {
                let date = DailyCalendar.date(of: d, start: start).map { DailyCalendar.say($0, weekday: false) } ?? ""
                let full = today.count > 0 ? "\(date) · \(PuzzleToday.inARow(today.count))" : date
                let short = DailyCalendar.date(of: d, start: start).map { DailyCalendar.sayShort($0) } ?? date
                ViewThatFits(in: .horizontal) {
                    Entry(symbol: "calendar", title: "Today", detail: full, check: today.solved, action: action)
                    Entry(symbol: "calendar", title: "Today", detail: today.count > 0 ? "\(short) · \(today.count) in a row" : short, check: today.solved, action: action)
                    Entry(symbol: "calendar", title: "Today", detail: today.count > 0 ? "\(today.count) in a row" : short, check: today.solved, action: action)
                }
                // The same words for VoiceOver whichever form fits.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(["Today", full, today.solved ? "Solved" : nil].compactMap { $0 }.joined(separator: ", "))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { action() }
                .accessibilityIdentifier("puzzles-today")
        }
    }
}

/// A quiet entry under a title: a symbol and a word, small words under it, and a check when done.
struct Entry: View {
    let symbol: String
    let title: String
    let detail: String?
    let check: Bool
    let action: () -> Void

    var body: some View {
        Button { Feel.shared.select(); action() } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(Z.soft)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(title).font(Z.medium(15))
                        if check { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Z.soft) }
                    }
                    if let detail { Text(detail).font(Z.text(12.5)).foregroundStyle(Z.dim) }
                }
            }
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 14).padding(.vertical, 7).frame(minHeight: 48)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Z.hair, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(Press())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, detail, check ? "Solved" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }
}
