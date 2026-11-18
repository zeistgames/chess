import Foundation
import os

/// Rings and arrows on a board, by square name, as a lesson gives them.
struct LessonMarks: Equatable, Sendable {
    var squares: [String] = []
    var arrows: [[String]] = []
    var isEmpty: Bool { squares.isEmpty && arrows.isEmpty }
}

/// One step of a lesson (docs/LESSONS.md, "Steps"). The three kinds share one shape; fields a kind does not use
/// stay empty.
struct LessonStep: Equatable, Sendable {
    enum Kind: String, Sendable { case show, move, pick }
    let kind: Kind
    let text: String
    /// The position, or nil to continue from the step before.
    var fen: String?
    var marks: LessonMarks?
    /// Whose side is at the bottom, when this step differs from the lesson.
    var side: String?
    /// show: moves played on the board when the step opens.
    var play: [String] = []
    /// move: the right moves in UCI. pick: the right squares.
    var accept: [String] = []
    /// A line for particular wrong moves (move) or squares (pick).
    var wrong: [String: String] = [:]
    /// move: good moves this lesson does not follow. They go back like a wrong move, with a line that says they work.
    var also: [String: String] = [:]
    var hint: String?
    var after: String?
    /// move: the opponent's answer to each accepted move. A single reply in the file answers every accepted move.
    var reply: [String: String] = [:]
    /// pick: every square must be found, not just one.
    var all = false
}

struct LessonPractice: Equatable, Sendable {
    let fen: String
    let side: String
}

struct Lesson: Equatable, Sendable, Identifiable {
    let id: String
    let course: String
    let title: String
    let line: String
    let side: String
    let steps: [LessonStep]
    let summary: String
    var practice: LessonPractice?
    /// The puzzle theme that practices this lesson's idea (a group id in the puzzle set's themes), if it has one.
    var puzzles: String?
}

/// The library as index.json lists it.
struct LessonIndex: Equatable, Sendable {
    struct Entry: Equatable, Sendable, Identifiable {
        let id: String
        let title: String
        let line: String
        let fen: String
        var marks: LessonMarks?
        let side: String
    }
    struct Chapter: Equatable, Sendable, Identifiable {
        let id: String
        let title: String
        var lessons: [Entry]
        /// Openings only: the moves in plain notation (small, secondary), the side that chooses it ("white" or
        /// "black"), the plain heading it is listed under, one plain sentence about it, the moves in UCI from the
        /// usual start (played on its page), and the position after them. An index written before `line` and `play`
        /// existed still reads; "either" is read as White's.
        var moves: String?
        var forSide: String?
        var group: String?
        var fen: String?
        var line: String?
        var play: [String]?
        /// The side the Openings page lists it under.
        var isBlack: Bool { forSide == "black" }
    }
    struct Course: Equatable, Sendable, Identifiable {
        let id: String
        let title: String
        let line: String
        var chapters: [Chapter]
        var lessonCount: Int { chapters.reduce(0) { $0 + $1.lessons.count } }
        var entries: [Entry] { chapters.flatMap(\.lessons) }
    }
    var courses: [Course]
}

/// Reads lessons and the index (docs/LESSONS.md). Everything this app knows about the format is in this one file.
/// Reading is strict: a field of the wrong kind, a move that is not UCI, a square that is not on the board or a
/// step without what its kind needs leaves that lesson out, with the reason logged. Fields the app does not use
/// (wins, mate, taught) are checked for their kind and then set aside; keys the format does not name are logged
/// and ignored, so a lesson written for a later app still opens.
enum LessonData {
    struct Fault: Error, CustomStringConvertible {
        let description: String
        init(_ d: String) { description = d }
    }

    static let log = Logger(subsystem: "st.zei.Chess", category: "lessons")

    // MARK: A lesson

    static func lesson(_ data: Data) throws -> Lesson {
        let root = try object(JSONSerialization.jsonObject(with: data), "lesson")
        let f = Fields(root, "lesson", known: ["id", "course", "title", "line", "side", "steps", "summary", "practice", "puzzles"])
        let id = try f.id("id")
        let course = try f.id("course")
        guard id.hasPrefix(course + "-") || id == course else { throw Fault("\(id): the id does not start with its course") }
        let side = try f.side("side")
        guard let rawSteps = root["steps"] as? [Any], !rawSteps.isEmpty else { throw Fault("\(id): no steps") }
        var steps: [LessonStep] = []
        for (n, raw) in rawSteps.enumerated() { steps.append(try step(raw, at: "\(id) step \(n + 1)")) }
        guard steps[0].fen != nil else { throw Fault("\(id): the first step has no fen") }
        var practice: LessonPractice?
        if let p = root["practice"] {
            let pf = Fields(try object(p, "\(id) practice"), "\(id) practice", known: ["fen", "side"])
            practice = LessonPractice(fen: try pf.fen("fen"), side: try pf.side("side"))
        }
        return Lesson(id: id, course: course, title: try f.string("title"), line: try f.string("line"), side: side,
                      steps: steps, summary: try f.string("summary"), practice: practice,
                      puzzles: try f.optional("puzzles") { try f.id($0) })
    }

    static func step(_ raw: Any, at: String) throws -> LessonStep {
        let d = try object(raw, at)
        let f = Fields(d, at, known: ["type", "text", "fen", "marks", "side", "play", "accept", "wrong", "also", "hint", "after", "reply", "wins", "mate", "taught", "sacrifice", "all"])
        guard let kind = (d["type"] as? String).flatMap(LessonStep.Kind.init(rawValue:)) else { throw Fault("\(at): unknown type") }
        var s = LessonStep(kind: kind, text: try f.string("text"))
        s.fen = try f.optional("fen") { try f.fen($0) }
        s.marks = try f.optional("marks") { _ in try marks(d["marks"]!, at: at) }
        s.side = try f.optional("side") { try f.side($0) }
        let unused: [String]
        switch kind {
        case .show:
            s.play = try f.optional("play") { try f.moves($0) } ?? []
            unused = ["accept", "wrong", "also", "hint", "after", "reply", "wins", "mate", "taught", "all"]
        case .move:
            s.accept = try f.moves("accept")
            guard !s.accept.isEmpty else { throw Fault("\(at): nothing to accept") }
            s.wrong = try f.optional("wrong") { try f.lines($0, key: PuzzleData.isUCI) } ?? [:]
            s.also = try f.optional("also") { try f.lines($0, key: PuzzleData.isUCI) } ?? [:]
            s.hint = try f.optional("hint") { try f.string($0) }
            s.after = try f.optional("after") { try f.string($0) }
            if let r = d["reply"] {
                if let one = r as? String {
                    guard PuzzleData.isUCI(one) else { throw Fault("\(at): reply is not a move") }
                    for m in s.accept { s.reply[m] = one }
                } else {
                    let each = try f.lines("reply", key: { s.accept.contains($0) })
                    guard each.values.allSatisfy(PuzzleData.isUCI) else { throw Fault("\(at): a reply is not a move") }
                    s.reply = each
                }
            }
            if let w = d["wins"] { guard let n = w as? NSNumber, !isBool(n), n.doubleValue == Double(n.intValue) else { throw Fault("\(at): wins") } }
            for k in ["mate", "taught"] { if let v = d[k] { guard let n = v as? NSNumber, isBool(n) else { throw Fault("\(at): \(k)") } } }
            unused = ["play", "all"]
        case .pick:
            s.accept = try f.squares("accept")
            guard !s.accept.isEmpty else { throw Fault("\(at): nothing to accept") }
            s.all = try f.optional("all") { try f.bool($0) } ?? false
            s.wrong = try f.optional("wrong") { try f.lines($0, key: { Square.index($0) != nil }) } ?? [:]
            s.hint = try f.optional("hint") { try f.string($0) }
            s.after = try f.optional("after") { try f.string($0) }
            unused = ["play", "also", "reply", "wins", "mate", "taught"]
        }
        if let k = unused.first(where: { d[$0] != nil }) { throw Fault("\(at): \(k) does not belong on a \(kind.rawValue) step") }
        return s
    }

    static func marks(_ raw: Any, at: String) throws -> LessonMarks {
        let f = Fields(try object(raw, "\(at) marks"), "\(at) marks", known: ["squares", "arrows"])
        var m = LessonMarks()
        m.squares = try f.optional("squares") { try f.squares($0) } ?? []
        if let a = f.d["arrows"] {
            guard let list = a as? [Any] else { throw Fault("\(at): arrows") }
            m.arrows = try list.map { item in
                guard let pair = item as? [String], pair.count == 2, pair.allSatisfy({ Square.index($0) != nil }), pair[0] != pair[1] else {
                    throw Fault("\(at): an arrow is not two squares")
                }
                return pair
            }
        }
        return m
    }

    // MARK: The index

    static func index(_ data: Data) throws -> LessonIndex {
        let root = try object(JSONSerialization.jsonObject(with: data), "index")
        guard let courses = root["courses"] as? [Any] else { throw Fault("index: no courses") }
        return LessonIndex(courses: try courses.enumerated().map { n, raw in
            let at = "index course \(n + 1)"
            let d = try object(raw, at)
            let f = Fields(d, at, known: ["id", "title", "line", "chapters"])
            guard let chapters = d["chapters"] as? [Any] else { throw Fault("\(at): no chapters") }
            let id = try f.id("id")
            return LessonIndex.Course(id: id, title: try f.string("title"), line: try f.string("line"),
                                      chapters: try chapters.enumerated().map { try chapter($1, at: "\(id) chapter \($0 + 1)") })
        })
    }

    static func chapter(_ raw: Any, at: String) throws -> LessonIndex.Chapter {
        let d = try object(raw, at)
        let f = Fields(d, at, known: ["id", "title", "lessons", "moves", "for", "group", "fen", "line", "play"])
        guard let lessons = d["lessons"] as? [Any] else { throw Fault("\(at): no lessons") }
        var c = LessonIndex.Chapter(id: try f.id("id"), title: try f.string("title"), lessons: try lessons.enumerated().map { n, raw in
            let at = "\(at) lesson \(n + 1)"
            let e = try object(raw, at)
            let ef = Fields(e, at, known: ["id", "title", "line", "fen", "marks", "side"])
            return LessonIndex.Entry(id: try ef.id("id"), title: try ef.string("title"), line: try ef.string("line"), fen: try ef.fen("fen"),
                                     marks: try ef.optional("marks") { _ in try marks(e["marks"]!, at: at) }, side: try ef.side("side"))
        })
        c.moves = try f.optional("moves") { try f.string($0) }
        c.forSide = try f.optional("for") { k in
            let s = try f.string(k)
            guard ["white", "black", "either"].contains(s) else { throw Fault("\(at): for") }
            return s
        }
        c.group = try f.optional("group") { try f.string($0) }
        c.fen = try f.optional("fen") { try f.fen($0) }
        c.line = try f.optional("line") { try f.string($0) }
        c.play = try f.optional("play") { try f.moves($0) }
        return c
    }

    // MARK: Pieces

    static func object(_ any: Any, _ at: String) throws -> [String: Any] {
        guard let d = any as? [String: Any] else { throw Fault("\(at): not an object") }
        return d
    }

    static func isBool(_ n: NSNumber) -> Bool { CFGetTypeID(n) == CFBooleanGetTypeID() }

    /// A FEN with eight ranks of eight squares and a side to move. Whether the position is legal is the checker's
    /// job (and the rules', which refuse it when the step opens).
    static func isFEN(_ fen: String) -> Bool {
        let fields = fen.split(separator: " ")
        guard fields.count >= 2, fields[1] == "w" || fields[1] == "b" else { return false }
        let ranks = fields[0].split(separator: "/", omittingEmptySubsequences: false)
        guard ranks.count == 8 else { return false }
        return ranks.allSatisfy { rank in
            var n = 0
            for ch in rank {
                if let d = ch.wholeNumberValue, (1...8).contains(d) { n += d }
                else if "pnbrqkPNBRQK".contains(ch) { n += 1 }
                else { return false }
            }
            return n == 8
        }
    }

    /// One object's fields, read with their kinds checked.
    struct Fields {
        let d: [String: Any]
        let at: String

        init(_ d: [String: Any], _ at: String, known: Set<String>) {
            self.d = d
            self.at = at
            for k in d.keys where !known.contains(k) { LessonData.log.notice("\(at, privacy: .public): unknown field \(k, privacy: .public) ignored") }
        }

        func string(_ k: String) throws -> String {
            guard let s = d[k] as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty else { throw Fault("\(at): \(k)") }
            return s
        }
        func bool(_ k: String) throws -> Bool {
            guard let n = d[k] as? NSNumber, isBool(n) else { throw Fault("\(at): \(k)") }
            return n.boolValue
        }
        func id(_ k: String) throws -> String {
            let s = try string(k)
            guard s.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) != nil else { throw Fault("\(at): \(k)") }
            return s
        }
        func side(_ k: String) throws -> String {
            let s = try string(k)
            guard s == "w" || s == "b" else { throw Fault("\(at): \(k)") }
            return s
        }
        func fen(_ k: String) throws -> String {
            let s = try string(k)
            guard isFEN(s) else { throw Fault("\(at): \(k) is not a FEN") }
            return s
        }
        func moves(_ k: String) throws -> [String] {
            guard let list = d[k] as? [String], list.allSatisfy(PuzzleData.isUCI) else { throw Fault("\(at): \(k) is not a list of moves") }
            return list
        }
        func squares(_ k: String) throws -> [String] {
            guard let list = d[k] as? [String], list.allSatisfy({ Square.index($0) != nil }) else { throw Fault("\(at): \(k) is not a list of squares") }
            return list
        }
        /// An object of lines, its keys checked.
        func lines(_ k: String, key ok: (String) -> Bool) throws -> [String: String] {
            guard let o = d[k] as? [String: Any] else { throw Fault("\(at): \(k)") }
            var out: [String: String] = [:]
            for (key, v) in o {
                guard ok(key), let s = v as? String, !s.isEmpty else { throw Fault("\(at): \(k) \(key)") }
                out[key] = s
            }
            return out
        }
        /// A field that may be missing; present, it must read.
        func optional<T>(_ k: String, _ read: (String) throws -> T) throws -> T? {
            guard let v = d[k], !(v is NSNull) else { return nil }
            return try read(k)
        }
    }
}
