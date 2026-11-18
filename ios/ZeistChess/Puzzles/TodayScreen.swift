import SwiftUI

/// The daily puzzle, pushed over the dock: the day's puzzle marked with its date, then the days in a row and the month
/// as a calendar, solved days filled and today ringed. Any past day from the start can be opened from the calendar
/// and played. Nothing is said about a missed day beyond one plain line on how a missed day can still count.
struct TodayScreen: View {
    @State var day: Int
    @Binding var path: [Route]
    @State private var model: PuzzleModel?
    @State private var progress = PuzzleProgress.load()
    @State private var month: (year: Int, month: Int)?
    /// Bumped when the date may have changed (midnight, a change of time zone, coming back to the app), so today is
    /// read again.
    @State private var tick = 0
    @State private var height: CGFloat = 800
    @Environment(\.scenePhase) private var phase
    private let puzzleSet = PuzzleSet.shared

    init(day: Int, path: Binding<[Route]>) {
        _day = State(initialValue: day)
        _path = path
    }

    private var list: PuzzleDailyList? { puzzleSet.daily }
    private var start: String { DailyCalendar.start(of: list) ?? "" }
    private var today: Int { _ = tick; return DailyCalendar.today(of: list) ?? 0 }
    /// The board leaves room for the count under it on a short screen.
    private var board: CGFloat { min(330, max(200, height - 330)) }
    private var isToday: Bool { day == today }
    private var dateText: String { DailyCalendar.date(of: day, start: start).map { DailyCalendar.say($0) } ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            PuzzleTop(label: isToday ? "Today" : "Daily puzzle", title: dateText, path: $path)
            ScrollView {
                VStack(spacing: 0) {
                    if let model {
                        PuzzleBoardArea(model: model, maxBoard: board).padding(.top, 10)
                    } else {
                        Text("Today's puzzle couldn't be read.").font(Z.text(15)).foregroundStyle(Z.soft).padding(.top, 40)
                    }
                    if let list { record(list).padding(.horizontal, 16).padding(.top, 14).frame(maxWidth: 520) }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            // The bar sits under the scrolling page, which stops short of it, so the count and calendar clear it.
            .safeAreaInset(edge: .bottom, spacing: 8) {
                if let model {
                    PuzzleGlassBar(model: model).padding(.horizontal, 16).padding(.bottom, 12).frame(maxWidth: 720)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in dateMoved() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in dateMoved() }
        .onChange(of: phase) { _, p in if p == .active { dateMoved() } }
        .background(Z.ground.ignoresSafeArea())
        .foregroundStyle(Z.ink)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: day) {
            // No daily without a start, and no day after today.
            guard let list, DailyCalendar.today(of: list) != nil, day <= today, let p = list.puzzle(day) else { model = nil; return }
            let m = PuzzleModel(source: .daily(day: day, puzzle: p, start: start))
            model = m
            if month == nil, let c = DailyCalendar.date(of: day, start: start) { month = (c.year!, c.month!) }
            await m.start()
        }
        .onChange(of: model?.phase) { _, _ in progress = PuzzleProgress.load() }
    }

    /// The date may have moved on: read today again, and the record with it.
    private func dateMoved() {
        tick += 1
        progress = PuzzleProgress.load()
    }

    // MARK: The count and the calendar

    private func record(_ list: PuzzleDailyList) -> some View {
        let solvedOn = progress.dailySolvedOn
        let count = DailyStreak.count(today: today, solvedOn: solvedOn)
        let shown = month ?? DailyCalendar.date(of: today, start: start).map { ($0.year!, $0.month!) } ?? (2026, 11)
        let cells = Self.cells(year: shown.year, month: shown.month, start: start)
        let recoverable = cells.contains { c in c.day.map { solvedOn[$0] == nil && DailyStreak.recoverable(day: $0, today: today) } ?? false }
        return VStack(alignment: .leading, spacing: 0) {
            if count > 0 {
                Text(PuzzleToday.inARow(count)).font(Z.title(26, relativeTo: .title2))
                    .accessibilityIdentifier("daily-count")
                    .padding(.horizontal, 8).padding(.bottom, 10)
            }
            monthBar(shown, list: list)
            calendar(cells, solvedOn: solvedOn)
            if recoverable {
                Text("A missed day still counts if you solve it within three days.")
                    .font(Z.text(13)).foregroundStyle(Z.dim).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10).padding(.horizontal, 8)
                    .accessibilityIdentifier("daily-note")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 16)
        .card(24)
    }

    private func monthBar(_ m: (year: Int, month: Int), list: PuzzleDailyList) -> some View {
        let first = DailyCalendar.parse(start)
        let now = DailyCalendar.date(of: today, start: start)
        let canBack = first.map { (m.year, m.month) > ($0.year!, $0.month!) } ?? false
        let canForward = now.map { (m.year, m.month) < ($0.year!, $0.month!) } ?? false
        let name = DailyCalendar.monthName(year: m.year, month: m.month)
        return HStack {
            Text(name).zLabel().accessibilityAddTraits(.isHeader).accessibilityIdentifier("daily-month").padding(.leading, 8)
            Spacer()
            Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle()) }
                .disabled(!canBack).opacity(canBack ? 1 : 0.25).accessibilityLabel("The month before").accessibilityIdentifier("daily-month-back")
            Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(Rectangle()) }
                .disabled(!canForward).opacity(canForward ? 1 : 0.25).accessibilityLabel("The month after").accessibilityIdentifier("daily-month-forward")
        }
        .font(.system(size: 14, weight: .medium)).foregroundStyle(Z.soft)
        .buttonStyle(Press())
        .padding(.bottom, 2)
    }

    private func shift(_ by: Int) {
        guard let m = month ?? DailyCalendar.date(of: today, start: start).map({ ($0.year!, $0.month!) }) else { return }
        var y = m.0, mo = m.1 + by
        if mo < 1 { mo = 12; y -= 1 } else if mo > 12 { mo = 1; y += 1 }
        Feel.shared.select()
        month = (y, mo)
    }

    private func calendar(_ cells: [Cell], solvedOn: [Int: Int]) -> some View {
        // A plain grid, not a lazy one: every day exists for VoiceOver and tests, wherever it is scrolled.
        let rows = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, w in
                    Text(w).font(Z.medium(11)).foregroundStyle(Z.dim).frame(maxWidth: .infinity, minHeight: 18).accessibilityHidden(true)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(row) { c in cell(c, solvedOn: solvedOn) }
                    ForEach(0..<(7 - row.count), id: \.self) { _ in Color.clear.frame(height: 44) }
                }
            }
        }
    }

    @ViewBuilder private func cell(_ c: Cell, solvedOn: [Int: Int]) -> some View {
        if let n = c.date {
            let d = c.day ?? Int.min
            let solved = solvedOn[d] != nil
            let open = d >= 0 && d <= today
            let isTodayCell = d == today
            let soft = !solved && DailyStreak.recoverable(day: d, today: today)
            let shown = d == day
            Button {
                guard open, d != day else { return }
                Feel.shared.select()
                day = d
            } label: {
                Text("\(n)")
                    .font(Z.medium(13.5)).monospacedDigit()
                    .foregroundStyle(solved ? Z.ground : open ? Z.soft : Z.dim.opacity(0.6))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(solved ? Z.ink : shown && !isTodayCell ? Z.wash.opacity(1.6) : .clear))
                    .overlay(Circle().strokeBorder(Z.ink, lineWidth: isTodayCell ? 1.5 : 0).padding(-3))
                    .overlay(Circle().strokeBorder(Z.soft, style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5])).opacity(soft ? 1 : 0))
                    // The circle is drawn at 34 points; the whole 44-point cell answers a tap.
                    .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(Press())
            .disabled(!open)
            .accessibilityLabel(c.label)
            .accessibilityValue([solved ? "Solved" : nil, isTodayCell ? "Today" : nil, soft ? "Can still count" : nil, shown ? "Shown" : nil].compactMap { $0 }.joined(separator: ", "))
            .accessibilityIdentifier("daily-day-\(n)")
        } else {
            Color.clear.frame(height: 44).accessibilityHidden(true)
        }
    }

    /// One square of the month: blank before the 1st, else a date and its day number.
    struct Cell: Identifiable {
        let id: Int
        let date: Int?
        let day: Int?
        let label: String
    }

    static func cells(year: Int, month: Int, start: String) -> [Cell] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let first = cal.date(from: DateComponents(year: year, month: month, day: 1, hour: 12)),
              let range = cal.range(of: .day, in: .month, for: first) else { return [] }
        let lead = cal.component(.weekday, from: first) - 1
        var out = (0..<lead).map { Cell(id: -1 - $0, date: nil, day: nil, label: "") }
        for n in range {
            let c = DateComponents(year: year, month: month, day: n)
            out.append(Cell(id: n, date: n, day: DailyCalendar.day(c, start: start), label: DailyCalendar.say(c)))
        }
        return out
    }
}

extension DailyCalendar {
    /// "Nov 20", where the full date doesn't fit.
    static func sayShort(_ c: DateComponents) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let d = cal.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: 12)) else { return "" }
        return d.formatted(Date.FormatStyle(locale: Fmt.us, timeZone: TimeZone(identifier: "UTC")!).month(.abbreviated).day())
    }

    /// "November 2026".
    static func monthName(year: Int, month: Int) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let d = cal.date(from: DateComponents(year: year, month: month, day: 1, hour: 12)) else { return "" }
        return d.formatted(Date.FormatStyle(locale: Fmt.us, timeZone: TimeZone(identifier: "UTC")!).month(.wide).year())
    }
}
