import XCTest
@testable import ZeistChess

/// Every engine the app carries: its data files (if it has any) downloaded and checked, then asked for a move in the
/// app's web view. Reads ZC_PACKS_BASE (for example https://engines.zei.st/), else ios/scripts/serve-packs.sh on the Mac.
/// Set ZC_SKIP_BIG=1 to skip engines whose download is over 50 MB.
@MainActor
final class AllPacksTests: XCTestCase {
    func testEveryPackPlaysAMove() async throws {
        let base = URL(string: ProcessInfo.processInfo.environment["ZC_PACKS_BASE"] ?? "http://127.0.0.1:8799/")!
        let probe = base.appending(path: "koivisto/default.net")
        var head = URLRequest(url: probe); head.httpMethod = "HEAD"
        guard let (_, r) = try? await URLSession.shared.data(for: head), (r as? HTTPURLResponse)?.statusCode == 200 else { throw XCTSkip("pack server not running") }
        Core.shared.boot()
        var report: [String] = []
        for (m, raw) in Shelf.bundledCatalog() {
            if ProcessInfo.processInfo.environment["ZC_SKIP_BIG"] != nil, m.downloadBytes > 50_000_000 { report.append("\(m.id): skipped (big)"); continue }
            let dir = Places.engines.appending(path: m.id)
            let had = FileManager.default.fileExists(atPath: dir.path)
            do {
                if m.needsDownload && !had {
                    try await Shelf.fetch(m, raw: raw, from: base.appending(path: m.id, directoryHint: .isDirectory)) { _ in }
                }
                let e = Engine(manifest: m, bundled: !m.needsDownload, installed: true)
                let began = Date()
                let settings = try await Core.shared.call("settings", ["manifest": e.coreArgs["manifest"]!, "level": 3, "seed": 5])
                let v = try await Core.shared.call("think", ["engine": e.coreArgs, "moves": ["e2e4"], "settings": settings]) as? [String: Any]
                let move = v?["move"] as? String ?? "none"
                report.append("\(m.id): \(move) in \(Int(Date().timeIntervalSince(began) * 1000)) ms")
                XCTAssertNotEqual(move, "none", m.id)
            } catch {
                report.append("\(m.id): FAILED \(error)")
                XCTFail("\(m.id): \(error)")
            }
            if !had { try? FileManager.default.removeItem(at: dir) }
        }
        print("PACKS REPORT\n" + report.joined(separator: "\n"))
    }
}
