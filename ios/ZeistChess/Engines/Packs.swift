import CryptoKit
import Foundation
import Observation

/// An engine pack's manifest.json (docs/PLAN.md, "Engine pack").
struct Manifest: Codable, Hashable, Sendable, Identifiable {
    struct File: Codable, Hashable, Sendable { var path: String; var bytes: Int; var sha256: String }
    var id: String
    var name: String
    var version: String
    var author: String?
    var license: String?
    var net_license: String?
    var source: String?
    var line: String?
    var files: [File]
    var entry: String
    var multipv: Bool?
    var total_bytes: Int?
    /// Kept as raw JSON: core/levels.js reads it.
    var strength: JSONValue?

    var bytes: Int { total_bytes ?? files.reduce(0) { $0 + $1.bytes } }

    /// The ratings this engine can be set to directly, on its own scale; nil when it has no such setting.
    var ratings: ClosedRange<Int>? {
        guard case .object(var o)? = strength else { return nil }
        if case .object(let inner)? = o["uci_elo"] { o = inner }
        else if case .string(let t)? = o["type"] ?? o["kind"], t == "uci_elo" {} else { return nil }
        guard case .number(let lo)? = o["min"], case .number(let hi)? = o["max"], lo < hi else { return nil }
        return Int(lo)...Int(hi)
    }
}

/// Any JSON value, passed through to the web view untouched.
enum JSONValue: Codable, Hashable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }

    var any: Any {
        switch self {
        case .string(let s): s
        case .number(let n): n
        case .bool(let b): b
        case .object(let o): o.mapValues(\.any)
        case .array(let a): a.map(\.any)
        case .null: NSNull()
        }
    }
}

/// Which of a pack's files are its program and which are its data. App Review does not allow downloading code after
/// install, so every program file ships in the app and only data files (networks, weights) are ever downloaded.
/// The one rule, mirrored in ios/scripts/bundle-engines.py and ios/scripts/packs-server.py: a file is data only if its
/// extension is not one of these.
enum PackFiles {
    static let programExtensions: Set<String> = ["js", "mjs", "wasm", "txt", "json"]

    static func isData(_ path: String) -> Bool {
        !programExtensions.contains((path as NSString).pathExtension.lowercased())
    }
}

extension Manifest {
    /// The files the app downloads.
    var dataFiles: [File] { files.filter { PackFiles.isData($0.path) } }
    /// What a download fetches, in bytes.
    var downloadBytes: Int { dataFiles.reduce(0) { $0 + $1.bytes } }
    /// Ready to play from the app alone.
    var needsDownload: Bool { !dataFiles.isEmpty }
}

/// Where the engines live on the device, and where their data comes from.
enum Places {
    static let support: URL = {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
    /// Downloaded data files, engines/<id>/, each folder with a copy of the app's manifest written last.
    static let engines = support.appending(path: "engines", directoryHint: .isDirectory)
    /// Every engine's program and manifest, and catalog.json (ios/scripts/bundle-engines.py).
    static let bundledEngines = Bundle.main.resourceURL!.appending(path: "engines", directoryHint: .isDirectory)
    static let core = Bundle.main.resourceURL!.appending(path: "core", directoryHint: .isDirectory)

    /// engines.zei.st (Config.xcconfig), where data files are fetched from. Debug builds may use a local address from
    /// Config.local.xcconfig, or -packs (tests), instead.
    static var packsURL: URL? {
        func read(_ key: String) -> URL? {
            guard let s = Bundle.main.object(forInfoDictionaryKey: key) as? String,
                  !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return URL(string: s)
        }
        #if DEBUG
        if let o = UserDefaults.standard.string(forKey: "packsURL"), let u = URL(string: o) { return u } // tests
        if let local = read("ZCPacksURLLocal") { return local }
        #endif
        return read("ZCPacksURL")
    }
}

/// One engine on the shelf.
struct Engine: Identifiable, Hashable, Sendable {
    var manifest: Manifest
    /// Needs nothing downloaded: it plays from the app alone, and can't be deleted.
    var bundled: Bool
    /// On the device and ready to play.
    var installed: Bool
    /// The manifest's own bytes, hashed: which exact pack a game was played with.
    var packSHA: String?

    var id: String { manifest.id }
    var name: String { manifest.name }
    /// The folder the web view loads the pack from (zchess://app/engines/<id>/).
    var base: String { "zchess://app/engines/\(manifest.id)/" }
}

enum Download: Equatable, Sendable {
    case running(Double)
    case failed(String)
}

/// The shelf: the engines the app carries, and which of them have their data on the device. Downloads, checks and
/// deletes data files. The list of engines and their programs change only with an app update.
@MainActor @Observable
final class Shelf {
    static let shared = Shelf()

    private(set) var engines: [Engine] = []
    private(set) var downloads: [String: Download] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    /// The app's catalog: each manifest with its exact bytes.
    let catalog: [(manifest: Manifest, raw: Data)]

    private init() {
        catalog = Self.bundledCatalog()
        // The catalog an earlier build fetched from the network; nothing reads it now.
        try? FileManager.default.removeItem(at: Places.support.appending(path: "catalog.json"))
        Self.migrate(catalog, in: Places.engines)
        rebuild()
    }

    static let bundledID = "stockfish-lite"

    func engine(_ id: String) -> Engine? { engines.first { $0.id == id } }

    /// Looks at the device again (after a reset, say). Nothing is read from the network.
    func refresh() { rebuild() }

    /// The app's catalog.json, and each manifest.json beside it byte for byte.
    nonisolated static func bundledCatalog(_ root: URL = Places.bundledEngines) -> [(manifest: Manifest, raw: Data)] {
        guard let data = try? Data(contentsOf: root.appending(path: "catalog.json")), let list = try? parseCatalog(data) else { return [] }
        return list.compactMap { m in
            guard let raw = try? Data(contentsOf: root.appending(path: "\(m.id)/manifest.json")),
                  let own = try? JSONDecoder().decode(Manifest.self, from: raw), own.id == m.id else { return nil }
            return (own, raw)
        }
    }

    /// catalog.json is a list of manifests, or an object holding one under "engines" or "packs".
    nonisolated static func parseCatalog(_ data: Data) throws -> [Manifest] {
        let d = JSONDecoder()
        if let list = try? d.decode([Manifest].self, from: data) { return list }
        struct Wrapped: Decodable { var engines: [Manifest]?; var packs: [Manifest]? }
        let w = try d.decode(Wrapped.self, from: data)
        guard let list = w.engines ?? w.packs else { throw URLError(.cannotParseResponse) }
        return list
    }

    private func rebuild() {
        engines = catalog.map { m, raw in
            Engine(manifest: m, bundled: !m.needsDownload,
                   installed: !m.needsDownload || Self.hasData(m, raw: raw, in: Places.engines.appending(path: m.id)),
                   packSHA: Self.sha(raw))
        }
    }

    /// The folder holds every data file at its size, and the app's own manifest, which a download writes last.
    nonisolated static func hasData(_ m: Manifest, raw: Data, in dir: URL) -> Bool {
        guard (try? Data(contentsOf: dir.appending(path: "manifest.json"))) == raw else { return false }
        return m.dataFiles.allSatisfy { size(ofFile: dir.appending(path: $0.path)) == $0.bytes }
    }

    nonisolated private static func size(ofFile u: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: u.path)[.size]) as? Int
    }

    /// Packs downloaded whole by earlier builds. One whose data files are the ones the app's manifest names (same paths,
    /// sizes and sha256, which were checked when it was downloaded) is kept: its program files are removed, since they
    /// now come only from the app, and the app's manifest takes the place of its own. Anything else in the engines
    /// folder (a pack the app no longer lists or whose data changed, a download cut short) is removed.
    /// Games and settings are elsewhere and untouched.
    nonisolated static func migrate(_ catalog: [(manifest: Manifest, raw: Data)], in root: URL) {
        let fm = FileManager.default
        guard let ids = try? fm.contentsOfDirectory(atPath: root.path) else { return }
        for id in ids {
            let dir = root.appending(path: id, directoryHint: .isDirectory)
            guard let (m, raw) = catalog.first(where: { $0.manifest.id == id }), m.needsDownload else {
                try? fm.removeItem(at: dir); continue
            }
            if hasData(m, raw: raw, in: dir) { strip(dir, keeping: m); continue }
            guard let old = try? Data(contentsOf: dir.appending(path: "manifest.json")),
                  let o = try? JSONDecoder().decode(Manifest.self, from: old),
                  Set(o.dataFiles.map { [$0.path, $0.sha256.lowercased(), "\($0.bytes)"] }) == Set(m.dataFiles.map { [$0.path, $0.sha256.lowercased(), "\($0.bytes)"] }),
                  m.dataFiles.allSatisfy({ size(ofFile: dir.appending(path: $0.path)) == $0.bytes }) else {
                try? fm.removeItem(at: dir); continue
            }
            strip(dir, keeping: m)
            do { try raw.write(to: dir.appending(path: "manifest.json"), options: .atomic) } catch { try? fm.removeItem(at: dir) }
        }
    }

    /// Removes every file in a pack's folder that isn't one of its data files or its manifest.
    nonisolated private static func strip(_ dir: URL, keeping m: Manifest) {
        let fm = FileManager.default
        let keep = Set(m.dataFiles.map(\.path) + ["manifest.json"])
        guard let it = fm.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        let base = dir.resolvingSymlinksInPath().path + "/"
        var drop: [URL] = []
        for case let u as URL in it where (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {
            let rel = String(u.resolvingSymlinksInPath().path.dropFirst(base.count))
            if !keep.contains(rel) { drop.append(u) }
        }
        for u in drop { try? fm.removeItem(at: u) }
    }

    nonisolated static func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Download

    func download(_ id: String) {
        guard let e = engine(id), !e.installed, tasks[id] == nil, let base = Places.packsURL,
              let raw = catalog.first(where: { $0.manifest.id == id })?.raw else { return }
        downloads[id] = .running(0)
        let m = e.manifest
        tasks[id] = Task { [weak self] in
            do {
                try await Self.fetch(m, raw: raw, from: base.appending(path: m.id, directoryHint: .isDirectory)) { p in
                    Task { @MainActor in if case .running = self?.downloads[id] { self?.downloads[id] = .running(p) } }
                }
                self?.downloads[id] = nil
                Feel.shared.select()
                Measure.engineInstalled(id)
            } catch is CancellationError {
                self?.downloads[id] = nil
            } catch {
                self?.downloads[id] = .failed(Self.say(error))
                ReviewRequest.shared.record(.trouble)
            }
            self?.tasks[id] = nil
            self?.rebuild()
        }
    }

    func cancel(_ id: String) {
        tasks[id]?.cancel()
    }

    func clearFailure(_ id: String) { if case .failed = downloads[id] { downloads[id] = nil } }

    /// Removes an engine's downloaded data and frees its space. Engines that need no download stay.
    func delete(_ id: String) {
        guard let e = engine(id), !e.bundled else { return }
        try? FileManager.default.removeItem(at: Places.engines.appending(path: id))
        rebuild()
    }

    /// Bytes used by downloaded data.
    func storageUsed() -> Int {
        Self.size(of: Places.engines)
    }

    func size(of id: String) -> Int {
        guard let e = engine(id) else { return 0 }
        if e.bundled { return 0 }
        return Self.size(of: Places.engines.appending(path: id))
    }

    nonisolated static func size(of dir: URL) -> Int {
        guard let it = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) else { return 0 }
        var n = 0
        for case let u as URL in it {
            let v = try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            n += v?.totalFileAllocatedSize ?? v?.fileSize ?? 0
        }
        return n
    }

    private static func say(_ error: Error) -> String {
        if let e = error as? PackError { return e.message }
        if let u = error as? URLError {
            switch u.code {
            case .notConnectedToInternet, .networkConnectionLost: return "You're offline."
            case .timedOut: return "The download stalled."
            case .cannotFindHost, .cannotConnectToHost: return "The engine server can't be reached."
            default: break
            }
        }
        return "The download failed."
    }

    /// Downloads an engine's data files, and only those, from base/<path>. Checks each one's size and sha256 against
    /// the app's manifest, and only then moves them into place, with the app's manifest written last. Nothing that
    /// could be executed is fetched: program files come from the app. A pack is never half there.
    nonisolated static func fetch(_ m: Manifest, raw: Data, into root: URL = Places.engines, from base: URL,
                                  progress: @escaping @Sendable (Double) -> Void) async throws {
        let fm = FileManager.default
        let data = m.dataFiles
        guard data.allSatisfy({ PackFiles.isData($0.path) }) else { throw PackError("This engine's program can't be downloaded.") }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appending(path: ".staging-\(m.id)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let total = max(1, data.reduce(0) { $0 + $1.bytes })
        var done = 0
        for f in data {
            try Task.checkCancellation()
            guard !f.path.split(separator: "/").contains(".."), !f.path.hasPrefix("/") else { throw PackError("This pack has a file outside its folder.") }
            let dest = staging.appending(path: f.path)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            let before = done
            let tmp = try await Fetcher.get(base.appending(path: f.path)) { got in
                progress(Double(before + min(got, f.bytes)) / Double(total))
            }
            defer { try? fm.removeItem(at: tmp) }
            let sha = try fileSHA(tmp)
            let size = (try fm.attributesOfItem(atPath: tmp.path)[.size] as? Int) ?? -1
            guard sha == f.sha256.lowercased(), size == f.bytes else { throw PackError("A file didn't match its checksum.") }
            try fm.moveItem(at: tmp, to: dest)
            done += f.bytes
            progress(Double(done) / Double(total))
        }
        try raw.write(to: staging.appending(path: "manifest.json"))
        let final = root.appending(path: m.id, directoryHint: .isDirectory)
        try? fm.removeItem(at: final)
        try fm.moveItem(at: staging, to: final)
        var v = URLResourceValues(); v.isExcludedFromBackup = true
        var f = final; try? f.setResourceValues(v)
    }

    nonisolated static func fileSHA(_ url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

struct PackError: Error { let message: String; init(_ m: String) { message = m } }

/// One file download with progress, into a temporary file.
final class Fetcher: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onBytes: @Sendable (Int) -> Void
    private var cont: CheckedContinuation<URL, Error>?
    private let lock = NSLock()

    private init(_ onBytes: @escaping @Sendable (Int) -> Void) { self.onBytes = onBytes }

    static func get(_ url: URL, onBytes: @escaping @Sendable (Int) -> Void) async throws -> URL {
        let f = Fetcher(onBytes)
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: cfg, delegate: f, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: url)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { c in
                f.lock.lock(); f.cont = c; f.lock.unlock()
                task.resume()
            }
        } onCancel: { task.cancel() }
    }

    private func finish(_ r: Result<URL, Error>) {
        lock.lock(); let c = cont; cont = nil; lock.unlock()
        c?.resume(with: r)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite _: Int64) {
        onBytes(Int(totalBytesWritten))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let h = downloadTask.response as? HTTPURLResponse, h.statusCode != 200 {
            finish(.failure(PackError(h.statusCode == 404 ? "This engine isn't on the server." : "The download failed.")))
            return
        }
        let keep = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        do { try FileManager.default.moveItem(at: location, to: keep); finish(.success(keep)) } catch { finish(.failure(error)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            if (error as? URLError)?.code == .cancelled { finish(.failure(CancellationError())) } else { finish(.failure(error)) }
        }
    }
}
