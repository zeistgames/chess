import Foundation

/// A group of puzzles by idea, from puzzles/themes.json: its name, its count in the whole set, and for each band the
/// ids it holds, in the band's own order.
struct PuzzleTheme: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let count: Int
    let bands: [Int: [String]]

    var ids: Set<String> { Set(bands.values.joined()) }
}

/// A theme's small board, hand-picked in Zeist (puzzles/theme-boards.json) so both apps show the same picture:
/// a position drawn from White's side, the move just played, the pieces involved ringed, the lines of force.
struct ThemeBoard: Equatable, Sendable {
    let fen: String
    let last: String?
    let rings: [String]
    let arrows: [[String]]

    var marks: BoardMarks { BoardMarks(LessonMarks(squares: rings, arrows: arrows)) }
}

/// The daily puzzle list, from puzzles/daily.json: the first day, and puzzles in a fixed order that only grows.
/// Without a start (missing or null in the file: the daily waits for Zeist's launch) there is no daily at all.
struct PuzzleDailyList: Equatable, Sendable {
    let start: String?
    let puzzles: [Puzzle]

    /// The puzzle for day n (0 is the start), or nil before the start or with no list.
    func puzzle(_ day: Int) -> Puzzle? { day >= 0 && !puzzles.isEmpty ? puzzles[day % puzzles.count] : nil }
}

/// The two files beside the puzzle set. Anything that does not parse is left out, never fatal.
enum PuzzleExtras {
    static func themes(_ data: Data) -> [PuzzleTheme] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let groups = root["groups"] as? [[String: Any]] else { return [] }
        return groups.compactMap { g in
            guard let id = g["id"] as? String, !id.isEmpty, let name = g["name"] as? String, !name.isEmpty,
                  let bands = g["bands"] as? [String: Any] else { return nil }
            var out: [Int: [String]] = [:]
            for (k, v) in bands {
                guard let b = Int(k), (1...PuzzleProgress.bands).contains(b), let s = v as? String else { continue }
                out[b] = s.split(separator: " ").map(String.init)
            }
            guard !out.isEmpty else { return nil }
            let count = (g["count"] as? NSNumber)?.intValue ?? out.values.reduce(0) { $0 + $1.count }
            return PuzzleTheme(id: id, name: name, count: count, bands: out)
        }
    }

    /// theme-boards.json: `{ about, boards: { "<group id>": { fen, last, rings, arrows } } }`. A board that does not
    /// read is left out (its theme gets a plain board).
    static func boards(_ data: Data) -> [String: ThemeBoard] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let boards = root["boards"] as? [String: Any] else { return [:] }
        var out: [String: ThemeBoard] = [:]
        for (id, v) in boards {
            guard let b = v as? [String: Any], let fen = b["fen"] as? String, LessonData.isFEN(fen) else { continue }
            let rings = (b["rings"] as? [String] ?? []).filter { Square.index($0) != nil }
            let arrows = (b["arrows"] as? [[String]] ?? []).filter { $0.count == 2 && $0.allSatisfy { Square.index($0) != nil } }
            let last = (b["last"] as? String).flatMap { PuzzleData.isUCI($0) ? $0 : nil }
            out[id] = ThemeBoard(fen: fen, last: last, rings: rings, arrows: arrows)
        }
        return out
    }

    /// daily.json: `{ start, puzzles: [[id, fen, moves, mate, band]] }`. A list with any unreadable row is refused
    /// whole: leaving one row out would shift every later day onto another puzzle.
    static func daily(_ data: Data) -> PuzzleDailyList? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["puzzles"] as? [[Any]] else { return nil }
        // A start that is missing, null or not a date means no daily yet.
        let start = (root["start"] as? String).flatMap { DailyCalendar.parse($0) != nil ? $0 : nil }
        var puzzles: [Puzzle] = []
        for r in rows {
            guard r.count >= 5, let band = (r[4] as? NSNumber)?.intValue, let p = PuzzleData.row(Array(r.prefix(4)), band: band) else { return nil }
            puzzles.append(p)
        }
        return PuzzleDailyList(start: start, puzzles: puzzles)
    }
}

/// Days of the daily puzzle: whole days from the list's start to the player's own calendar date. Midnight is local.
enum DailyCalendar {
    /// "2026-11-16" as year, month, day.
    static func parse(_ s: String) -> DateComponents? {
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]), (1...31).contains(p[2]) else { return nil }
        return DateComponents(year: p[0], month: p[1], day: p[2])
    }

    /// A calendar date counted in days, the same in every time zone.
    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private static func serial(_ c: DateComponents) -> Int? {
        guard let d = utc.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: 12)) else { return nil }
        return Int((d.timeIntervalSince1970 / 86_400).rounded(.down))
    }

    /// The day number of a calendar date (negative before the start).
    static func day(_ date: DateComponents, start: String) -> Int? {
        guard let s = parse(start).flatMap(serial), let d = serial(date) else { return nil }
        return d - s
    }

    /// The day number of a moment, read on the player's own calendar (the device's time zone).
    static func day(at moment: Date, start: String, calendar: Calendar = .current) -> Int? {
        day(calendar.dateComponents([.year, .month, .day], from: moment), start: start)
    }

    /// The calendar date of a day number.
    static func date(of day: Int, start: String) -> DateComponents? {
        guard let s = parse(start), let d = utc.date(from: DateComponents(year: s.year, month: s.month, day: s.day, hour: 12)),
              let out = utc.date(byAdding: .day, value: day, to: d) else { return nil }
        return utc.dateComponents([.year, .month, .day, .weekday], from: out)
    }

    /// "Tuesday, November 17", in American English whatever the phone's region.
    static func say(_ c: DateComponents, weekday: Bool = true) -> String {
        guard let d = utc.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: 12)) else { return "" }
        var f = Date.FormatStyle(locale: Fmt.us, timeZone: TimeZone(identifier: "UTC")!).month(.wide).day()
        if weekday { f = f.weekday(.wide) }
        return d.formatted(f)
    }

    /// The daily's first day: the file's, or in a debug build the one given with -daily-start (none for no start).
    @MainActor static func start(of list: PuzzleDailyList?) -> String? {
        guard let list else { return nil }
        #if DEBUG
        if let s = Debug.value("-daily-start") { return parse(s) != nil ? s : nil }
        #endif
        return list.start
    }

    /// Today's day number, or nil when there is no daily today (no list, no start, or before the start).
    @MainActor static func today(of list: PuzzleDailyList?) -> Int? {
        guard let start = start(of: list), let d = day(at: now(), start: start), d >= 0 else { return nil }
        return d
    }

    /// Now, or the date given to a debug build with -today 2026-11-20.
    @MainActor static func now() -> Date {
        #if DEBUG
        if let s = Debug.value("-today"), let c = parse(s) {
            var cal = Calendar.current
            cal.timeZone = .current
            if let d = cal.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: 12)) { return d }
        }
        #endif
        return Date()
    }
}

/// The daily record for one day: the puzzle, whether it took a miss or Show the move first, and the day number it
/// was finished on. Written at the first finish of the day's puzzle (Show the move counts, as a miss).
struct DailyRecord: Codable, Equatable, Sendable {
    var id: String
    var missed: Int
    var on: Int

    /// Two copies of one day on a device (a guest's joining an account's): the earlier finish wins, and on the
    /// same day the one already there (a). Never the one with fewer misses.
    static func merge(_ a: DailyRecord, _ b: DailyRecord) -> DailyRecord { b.on < a.on ? b : a }
}

/// Days in a row, the one rule shared with Zeist (its public/s/chess/daily.js; the cases both check against are
/// puzzles/streak-cases.json). A day counts when it was solved on or after its own date and within `window` days of
/// it (a solve dated after today, from a clock running ahead, still counts within the window). Walking back from today: a counting day adds one; an unsolved day still within the window is passed
/// over (it can be made up); anything else ends the walk, as does the start of the list.
enum DailyStreak {
    static let window = 3

    /// - Parameters:
    ///   - today: today's day number.
    ///   - solvedOn: for each solved day, the day number it was solved on.
    static func count(today: Int, solvedOn: [Int: Int], window: Int = DailyStreak.window) -> Int {
        var n = 0
        var d = today
        while d >= 0 {
            if let on = solvedOn[d] {
                guard counts(day: d, on: on, window: window) else { break }
                n += 1
            } else if today - d > window {
                break
            }
            d -= 1
        }
        return n
    }

    /// Whether a solved day joins the count.
    static func counts(day: Int, on: Int, window: Int = DailyStreak.window) -> Bool { on >= day && on - day <= window }

    /// Whether an unsolved past day can still join the count if solved today.
    static func recoverable(day: Int, today: Int, window: Int = DailyStreak.window) -> Bool { day < today && today - day <= window }
}
