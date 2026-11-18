import Foundation

/// One puzzle: a position, and the line that solves it. The first move of the line is the opponent's; then the
/// solver's and the opponent's in turn, ending on the solver's.
struct Puzzle: Equatable, Sendable {
    /// The Lichess puzzle id.
    let id: String
    /// The position before the opponent's first move.
    let fen: String
    /// The line in UCI ("e2e4", "e7e8q").
    let moves: [String]
    /// N for a mate in N, else 0.
    let mate: Int
    /// The band of difficulty it came from, 1 (easiest) to 8.
    let band: Int

    /// The side the solver plays, "w" or "b": the side not to move in the FEN, since the opponent moves first.
    var solver: String { fen.split(separator: " ").dropFirst().first == "w" ? "b" : "w" }
}

/// The puzzle set as Zeist builds it (puzzles/README.md). Everything this app knows about the file format is in
/// this one file: index.json lists bands and their files; each file is {"band": n, "puzzles": [[id, fen, moves,
/// mate], ...]}. Anything that does not parse is skipped, never fatal.
enum PuzzleData {
    struct Band: Equatable, Sendable {
        let band: Int
        let files: [String]
    }

    /// The bands listed in index.json, in order. Empty when it does not parse.
    static func index(_ data: Data) -> [Band] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bands = root["bands"] as? [[String: Any]] else { return [] }
        return bands.compactMap { b in
            guard let n = (b["band"] as? NSNumber)?.intValue, n >= 1,
                  let files = b["files"] as? [String] else { return nil }
            return Band(band: n, files: files.filter { !$0.contains("/") && $0.hasSuffix(".json") })
        }
        .sorted { $0.band < $1.band }
    }

    /// The puzzles in one file, in their shipped order. Rows that do not parse are left out.
    static func puzzles(_ data: Data, band: Int) -> [Puzzle] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["puzzles"] as? [Any] else { return [] }
        return rows.compactMap { row(($0 as? [Any]) ?? [], band: band) }
    }

    /// One row, [id, fen, "uci uci ...", mate], checked: an id, a FEN with a side to move, an even line of at least
    /// two moves in UCI, and a whole number for the mate.
    static func row(_ r: [Any], band: Int) -> Puzzle? {
        guard r.count >= 4, let id = r[0] as? String, !id.isEmpty, let fen = r[1] as? String, let line = r[2] as? String,
              let mateNumber = r[3] as? NSNumber, CFGetTypeID(mateNumber) != CFBooleanGetTypeID() else { return nil }
        let mate = mateNumber.intValue
        guard Double(mate) == mateNumber.doubleValue, mate >= 0 else { return nil }
        let fields = fen.split(separator: " ")
        guard fields.count >= 2, fields[0].split(separator: "/").count == 8, fields[1] == "w" || fields[1] == "b" else { return nil }
        let moves = line.split(separator: " ").map(String.init)
        guard moves.count >= 2, moves.count % 2 == 0, moves.allSatisfy(isUCI) else { return nil }
        return Puzzle(id: id, fen: fen, moves: moves, mate: mate, band: band)
    }

    static func isUCI(_ m: String) -> Bool {
        let c = Array(m)
        guard c.count == 4 || c.count == 5 else { return false }
        let file: (Character) -> Bool = { ("a"..."h").contains($0) }
        let rank: (Character) -> Bool = { ("1"..."8").contains($0) }
        return file(c[0]) && rank(c[1]) && file(c[2]) && rank(c[3]) && (c.count == 4 || "qrbn".contains(c[4]))
    }
}

/// The bundled set (puzzles/ in the app), read a file at a time as it is needed.
@MainActor
final class PuzzleSet {
    static let shared = PuzzleSet(folder: Bundle.main.resourceURL!.appending(path: "puzzles", directoryHint: .isDirectory))

    let folder: URL
    private(set) lazy var bands: [PuzzleData.Band] = (try? Data(contentsOf: folder.appending(path: "index.json"))).map(PuzzleData.index) ?? []
    private var files: [String: [Puzzle]] = [:]
    /// Files that couldn't be read: not known, never taken for used up.
    private var unread: Set<String> = []

    init(folder: URL) { self.folder = folder }

    /// The puzzles of one file of a band.
    func puzzles(_ file: String, band: Int) -> [Puzzle] {
        if let p = files[file] { return p }
        guard let data = try? Data(contentsOf: folder.appending(path: file)) else { unread.insert(file); return [] }
        let p = PuzzleData.puzzles(data, band: band)
        files[file] = p
        return p
    }

    /// Every puzzle of a band, in order.
    func band(_ n: Int) -> [Puzzle] {
        bands.first { $0.band == n }.map { b in b.files.flatMap { puzzles($0, band: n) } } ?? []
    }

    /// Every puzzle of a band, or nil when the band, or any file of it, can't be read now (PuzzleProgress.next(in:)).
    func bandIfRead(_ n: Int) -> [Puzzle]? {
        guard let b = bands.first(where: { $0.band == n }) else { return nil }
        let list = b.files.flatMap { puzzles($0, band: n) }
        return b.files.contains(where: unread.contains) ? nil : list
    }

    func find(_ id: String, band: Int) -> Puzzle? { byID(band)[id] }

    private var index: [Int: [String: Puzzle]] = [:]
    private func byID(_ b: Int) -> [String: Puzzle] {
        if let d = index[b] { return d }
        let d = Dictionary(self.band(b).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        index[b] = d
        return d
    }

    /// The groups by idea (themes.json), in their display order.
    private(set) lazy var themes: [PuzzleTheme] = (try? Data(contentsOf: folder.appending(path: "themes.json"))).map(PuzzleExtras.themes) ?? []
    /// The daily list (daily.json), or nil when it is missing or does not read.
    private(set) lazy var daily: PuzzleDailyList? = (try? Data(contentsOf: folder.appending(path: "daily.json"))).flatMap(PuzzleExtras.daily)

    /// Each theme's small board (theme-boards.json), by group id.
    private(set) lazy var themeBoards: [String: ThemeBoard] = (try? Data(contentsOf: folder.appending(path: "theme-boards.json"))).map(PuzzleExtras.boards) ?? [:]

    func theme(_ id: String) -> PuzzleTheme? { themes.first { $0.id == id } }

    /// A theme's puzzles in one band, in the band's order; ids not in this copy of the set are passed over.
    func puzzles(of theme: PuzzleTheme, band b: Int) -> [Puzzle] {
        let d = byID(b)
        return (theme.bands[b] ?? []).compactMap { d[$0] }
    }
}
