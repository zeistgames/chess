import Foundation

/// A time control: minutes for the game and seconds added after each move ("3+2").
struct TimeControl: Codable, Hashable, Sendable {
    /// Seconds each side starts with.
    var base: Int
    /// Seconds added after each move.
    var increment: Int

    enum Kind: String, Codable, Sendable, CaseIterable {
        case bullet, blitz, rapid, classical
        var name: String { rawValue.capitalized }
    }

    /// As PGN's TimeControl tag writes it: "180+2".
    var pgn: String { "\(base)+\(increment)" }

    init(base: Int, increment: Int) {
        self.base = max(1, base)
        self.increment = max(0, increment)
    }

    init?(pgn: String) {
        let p = pgn.split(separator: "+")
        guard p.count == 2, let b = Int(p[0]), let i = Int(p[1]), b > 0, i >= 0 else { return nil }
        self.init(base: b, increment: i)
    }

    static func minutes(_ m: Int, _ inc: Int = 0) -> TimeControl { TimeControl(base: m * 60, increment: inc) }

    /// "3 min" without increment, "3+2" with one. Minutes under one are said in seconds.
    var name: String {
        let m = base % 60 == 0 ? "\(base / 60)" : base < 60 ? "\(base)s" : String(format: "%.1f", Double(base) / 60)
        return increment == 0 ? (base % 60 == 0 ? "\(m) min" : m) : "\(m)+\(increment)"
    }

    /// Bullet, blitz, rapid or classical, by the expected length of a game of 40 moves (as Lichess counts).
    var kind: Kind {
        let expected = base + 40 * increment
        if expected < 180 { return .bullet }
        if expected < 480 { return .blitz }
        if expected < 1500 { return .rapid }
        return .classical
    }

    /// Below this many seconds the clock turns to its low-time color and the phone taps once.
    var lowTime: Double { min(20, max(10, Double(base) * 0.1)) }

    /// The standard controls offered in the picker, grouped.
    static let presets: [(Kind, [TimeControl])] = [
        (.bullet, [.minutes(1), .minutes(1, 1), .minutes(2, 1)]),
        (.blitz, [.minutes(3), .minutes(3, 2), .minutes(5), .minutes(5, 3)]),
        (.rapid, [.minutes(10), .minutes(15, 10)]),
    ]
}

/// Two clocks. The side to move counts down; a move adds the increment to the side that made it and starts the
/// other. The clocks start with White's first move, so the first move is free. Times are seconds; `now` is any
/// steady clock (the app passes the system uptime), so tests can drive it by hand.
struct ChessClock: Equatable, Sendable {
    let control: TimeControl
    private(set) var white: Double
    private(set) var black: Double
    /// Whose clock runs: "w", "b", or nil before the first move and after the end.
    private(set) var running: String?
    /// When the running clock last started; nil while paused.
    private var since: Double?
    private(set) var paused: Bool

    init(control: TimeControl, white: Double? = nil, black: Double? = nil, running: String? = nil, paused: Bool = true, at now: Double = 0) {
        self.control = control
        self.white = white ?? Double(control.base)
        self.black = black ?? Double(control.base)
        self.running = running
        self.paused = paused
        self.since = paused || running == nil ? nil : now
    }

    func remaining(_ side: String, at now: Double) -> Double {
        let left = side == "w" ? white : black
        guard running == side, let since else { return max(0, left) }
        return max(0, left - (now - since))
    }

    /// Seconds the running side has left, or nil when no clock runs.
    func untilFlag(at now: Double) -> Double? {
        guard let running, since != nil else { return nil }
        return remaining(running, at: now)
    }

    /// The side whose time is up, if any.
    func flagged(at now: Double) -> String? {
        guard let r = running, remaining(r, at: now) <= 0 else { return nil }
        return r
    }

    /// `side` has just moved: its time stops, it gains the increment (once its clock has started), the other's starts.
    mutating func moved(_ side: String, at now: Double) {
        // Once a side's time has run out the game is over: a move made after it changes nothing.
        if running == side, remaining(side, at: now) <= 0 { return }
        if running == side {
            set(side, remaining(side, at: now) + Double(control.increment))
        }
        running = side == "w" ? "b" : "w"
        since = paused ? nil : now
    }

    mutating func pause(at now: Double) {
        guard !paused else { return }
        fold(at: now)
        paused = true
    }

    mutating func resume(at now: Double) {
        guard paused else { return }
        paused = false
        if running != nil { since = now }
    }

    /// The game is over: both clocks stop where they are.
    mutating func stop(at now: Double) {
        fold(at: now)
        running = nil
    }

    private mutating func fold(at now: Double) {
        if let r = running { set(r, remaining(r, at: now)) }
        since = nil
    }

    private mutating func set(_ side: String, _ v: Double) {
        if side == "w" { white = v } else { black = v }
    }

    /// "3:00", "0:42", "0:09.4" under ten seconds, "1:05:00" over an hour.
    static func say(_ seconds: Double) -> String {
        let s = max(0, seconds)
        if s < 10 {
            let tenths = Int((s * 10).rounded(.down))
            return "0:0\(tenths / 10).\(tenths % 10)"
        }
        let whole = Int(s.rounded(.down))
        let h = whole / 3600, m = (whole % 3600) / 60, sec = whole % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// For VoiceOver: "2 minutes 58 seconds", "9 seconds".
    static func spoken(_ seconds: Double) -> String {
        let whole = Int(max(0, seconds).rounded(.down))
        let m = whole / 60, s = whole % 60
        var parts: [String] = []
        if m > 0 { parts.append("\(m) \(m == 1 ? "minute" : "minutes")") }
        if s > 0 || m == 0 { parts.append("\(s) \(s == 1 ? "second" : "seconds")") }
        return parts.joined(separator: " ")
    }

    /// As PGN's %clk comment writes it: "0:02:58.4".
    static func pgn(ms: Int) -> String {
        let t = max(0, ms) / 100
        let tenths = t % 10, whole = t / 10
        return String(format: "%d:%02d:%02d.%d", whole / 3600, (whole % 3600) / 60, whole % 60, tenths)
    }
}
