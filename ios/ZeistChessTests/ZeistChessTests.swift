import XCTest
@testable import ZeistChess
import WebKit

final class SquareTests: XCTestCase {
    func testNamesAndIndices() {
        XCTAssertEqual(Square.name(0), "a8")
        XCTAssertEqual(Square.name(63), "h1")
        XCTAssertEqual(Square.index("e4"), 36)
        XCTAssertNil(Square.index("i9"))
    }

    func testBoardFromFEN() {
        let b = Square.board(fromFEN: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1")
        XCTAssertEqual(b.count, 64)
        XCTAssertEqual(b[0], "bR")
        XCTAssertEqual(b[36], "wP")
        XCTAssertEqual(b[52], "")
    }
}

final class LogTests: XCTestCase {
    private func record(moves: [String], san: [String], result: String?, player: String = "w") -> GameRecord {
        var r = GameRecord(startFEN: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", fen: "", player: player,
                           engineID: "stockfish-lite", engineName: "Stockfish Lite", engineVersion: "19.0.1", packSHA: "abc",
                           level: 3, adaptive: true, engineSettings: nil, seed: 7, appVersion: "1.0 (1)")
        r.moves = moves; r.san = san; r.result = result
        return r
    }

    func testOutcomeFromThePlayersSide() {
        XCTAssertEqual(record(moves: [], san: [], result: "1-0").outcome, "win")
        XCTAssertEqual(record(moves: [], san: [], result: "1-0", player: "b").outcome, "loss")
        XCTAssertEqual(record(moves: [], san: [], result: "1/2-1/2").outcome, "draw")
        XCTAssertNil(record(moves: [], san: [], result: "*").outcome)
    }

    func testPGN() {
        let r = record(moves: ["f2f3", "e7e5", "g2g4", "d8h4"], san: ["f3", "e5", "g4", "Qh4#"], result: "0-1")
        let pgn = GameLog.pgn(r)
        XCTAssertTrue(pgn.contains("[White \"You\"]"))
        XCTAssertTrue(pgn.contains("[Black \"Stockfish Lite 19.0.1, level 3\"]"))
        XCTAssertTrue(pgn.contains("1. f3 e5 2. g4 Qh4# 0-1"))
    }

    func testRecordRoundTrips() throws {
        let r = record(moves: ["e2e4"], san: ["e4"], result: nil)
        let back = try GameLog.decoder.decode(GameRecord.self, from: GameLog.encoder.encode(r))
        XCTAssertEqual(back.moves, r.moves)
        XCTAssertEqual(back.startedAt.timeIntervalSince1970, r.startedAt.timeIntervalSince1970, accuracy: 0.001)
    }
}

final class PackTests: XCTestCase {
    func testCatalogShapes() throws {
        let m = #"{"id":"x","name":"X","version":"1","files":[{"path":"a.js","bytes":1,"sha256":"00"}],"entry":"a.js","strength":{"type":"uci_elo","min":1,"max":2}}"#
        XCTAssertEqual(try Shelf.parseCatalog(Data("[\(m)]".utf8)).map(\.id), ["x"])
        XCTAssertEqual(try Shelf.parseCatalog(Data(#"{"engines":[\#(m)]}"#.utf8)).map(\.id), ["x"])
        XCTAssertThrowsError(try Shelf.parseCatalog(Data("{}".utf8)))
    }

    func testSchemeHandlerStaysInItsFolders() {
        XCTAssertNil(SchemeHandler.file(for: URL(string: "zchess://app/core/../../etc/passwd")!))
        XCTAssertNil(SchemeHandler.file(for: URL(string: "zchess://other/core/rules.js")!))
        XCTAssertNotNil(SchemeHandler.file(for: URL(string: "zchess://app/core/rules.js")!))
        XCTAssertNotNil(SchemeHandler.file(for: URL(string: "zchess://app/engines/stockfish-lite/manifest.json")!))
        XCTAssertEqual(SchemeHandler.mime("wasm"), "application/wasm")
    }

    func testTheRuleForData() {
        for p in ["a.js", "ort/x.mjs", "e.wasm", "LICENSE.txt", "manifest.json", "A.JS"] { XCTAssertFalse(PackFiles.isData(p), p) }
        for p in ["n.nnue", "w.onnx", "default.net", "p.bin", "verbatim.nn", "e.pnn", "noextension"] { XCTAssertTrue(PackFiles.isData(p), p) }
    }

    /// The rule, proved on what ships: nothing the downloader would fetch is a program, and every program file a
    /// manifest names is in the app with its sha256. Full Stockfish is left out.
    func testTheAppCarriesEveryProgram() throws {
        let catalog = Shelf.bundledCatalog()
        XCTAssertEqual(catalog.map(\.manifest.id), ["stockfish-lite", "fairy-stockfish", "maia", "arasan", "clover", "caissa",
                                                    "plentychess", "halogen", "koivisto", "ethereal", "zeist"])
        for (m, _) in catalog {
            for f in m.dataFiles {
                XCTAssertFalse(PackFiles.programExtensions.contains((f.path as NSString).pathExtension.lowercased()), "\(m.id): \(f.path)")
            }
            XCTAssertFalse(PackFiles.isData(m.entry), m.id)
            let dir = Places.bundledEngines.appending(path: m.id)
            for f in m.files where !PackFiles.isData(f.path) {
                XCTAssertEqual(try? Shelf.fileSHA(dir.appending(path: f.path)), f.sha256.lowercased(), "\(m.id): \(f.path)")
            }
            // And no data file is in the app.
            for f in m.dataFiles { XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appending(path: f.path).path), "\(m.id): \(f.path)") }
        }
        XCTAssertEqual(Set(catalog.filter { !$0.manifest.needsDownload }.map(\.manifest.id)), ["stockfish-lite", "fairy-stockfish", "ethereal", "zeist"])
    }

    @MainActor
    func testEnginesWithNoDataAreReady() {
        for id in ["stockfish-lite", "fairy-stockfish", "ethereal", "zeist"] {
            let e = Shelf.shared.engine(id)
            XCTAssertEqual(e?.bundled, true, id)
            XCTAssertEqual(e?.installed, true, id)
        }
        XCTAssertNil(Shelf.shared.engine("stockfish"), "full Stockfish isn't in this build")
        XCTAssertEqual(Shelf.shared.engine("koivisto")?.bundled, false)
    }

    /// A pack with one data file, served from a folder on disk (file URLs need no server).
    private func fixture(sha: String? = nil) throws -> (Manifest, Data, URL, URL) {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "packs-\(UUID().uuidString)", directoryHint: .isDirectory)
        let served = tmp.appending(path: "served/test-pack", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: served, withIntermediateDirectories: true)
        let net = Data((0..<5000).map { UInt8($0 % 251) })
        try net.write(to: served.appending(path: "net.nnue"))
        try Data("bad".utf8).write(to: served.appending(path: "engine.js"))
        let m = Manifest(id: "test-pack", name: "Test", version: "1",
                         files: [.init(path: "engine.js", bytes: 3, sha256: "00"), .init(path: "net.nnue", bytes: net.count, sha256: sha ?? Shelf.sha(net))],
                         entry: "engine.js")
        return (m, try JSONEncoder().encode(m), served, tmp.appending(path: "engines", directoryHint: .isDirectory))
    }

    func testDownloadFetchesOnlyData() async throws {
        let (m, raw, served, root) = try fixture()
        try await Shelf.fetch(m, raw: raw, into: root, from: served) { _ in }
        let dir = root.appending(path: m.id)
        XCTAssertTrue(Shelf.hasData(m, raw: raw, in: dir))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appending(path: "engine.js").path), "programs are never downloaded")
        XCTAssertEqual(try Data(contentsOf: dir.appending(path: "manifest.json")), raw)
    }

    func testADataFileWithTheWrongHashIsRefused() async throws {
        let (m, raw, served, root) = try fixture(sha: String(repeating: "ab", count: 32))
        do { try await Shelf.fetch(m, raw: raw, into: root, from: served) { _ in }; XCTFail("should refuse") } catch {
            XCTAssertEqual((error as? PackError)?.message, "A file didn't match its checksum.")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: m.id).path))
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: root.path))?.count ?? 0, 0, "nothing left behind")
    }

    /// A pack an earlier build downloaded whole: kept when its data matches, its programs dropped; otherwise removed.
    func testWholePacksFromEarlierBuilds() throws {
        let (m, raw, served, root) = try fixture()
        let fm = FileManager.default
        func oldPack(_ id: String, manifest: Manifest) throws -> URL {
            let dir = root.appending(path: id, directoryHint: .isDirectory)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for f in ["net.nnue", "engine.js"] { try fm.copyItem(at: served.appending(path: f), to: dir.appending(path: f)) }
            var old = manifest; old.version = "old build" // its own manifest bytes, not the app's
            try JSONEncoder().encode(old).write(to: dir.appending(path: "manifest.json"))
            return dir
        }
        let kept = try oldPack(m.id, manifest: m)
        var other = m; other.id = "changed"
        other.files[1].sha256 = String(repeating: "cd", count: 32)
        let changed = try oldPack("changed", manifest: other)
        var otherNow = other; otherNow.files[1].sha256 = m.files[1].sha256 // the app now expects different data
        let gone = try oldPack("not-listed", manifest: m)
        Shelf.migrate([(m, raw), (otherNow, try JSONEncoder().encode(otherNow))], in: root)
        XCTAssertTrue(Shelf.hasData(m, raw: raw, in: kept))
        XCTAssertFalse(fm.fileExists(atPath: kept.appending(path: "engine.js").path))
        XCTAssertFalse(fm.fileExists(atPath: changed.path))
        XCTAssertFalse(fm.fileExists(atPath: gone.path))
    }

    func testDownloadFromNowhereFails() async throws {
        let (m, raw, _, root) = try fixture()
        do { try await Shelf.fetch(m, raw: raw, into: root, from: URL(string: "http://127.0.0.1:1/none/")!) { _ in }; XCTFail("should fail") } catch {}
    }

    /// Needs ios/scripts/serve-packs.sh (or packs-server.py) on the Mac; the simulator reaches its loopback.
    func testTheLocalServerServesOnlyData() async throws {
        let base = URL(string: "http://127.0.0.1:8799/koivisto/")!
        guard let (_, r) = try? await URLSession.shared.data(from: base.appending(path: "default.net")), (r as? HTTPURLResponse)?.statusCode == 200 else {
            throw XCTSkip("pack server not running")
        }
        for p in ["koivisto.js", "koivisto.wasm", "manifest.json", "LICENSE.txt"] {
            let (_, r) = try await URLSession.shared.data(from: base.appending(path: p))
            XCTAssertEqual((r as? HTTPURLResponse)?.statusCode, 404, p)
        }
    }
}

@MainActor
final class CoreTests: XCTestCase {
    func testRulesAndEngineInTheWebView() async throws {
        Core.shared.boot()
        let s = try await Core.shared.decode(Snapshot.self, "state", ["moves": ["e2e4", "e7e5"]])
        XCTAssertEqual(s.turn, "w")
        XCTAssertEqual(s.legal.count, 29)
        let e = try XCTUnwrap(Shelf.shared.engine(Shelf.bundledID))
        let settings = try await Core.shared.call("settings", ["manifest": e.coreArgs["manifest"]!, "level": 3, "seed": 1])
        let v = try await Core.shared.call("think", ["engine": e.coreArgs, "moves": ["e2e4"], "settings": settings]) as? [String: Any]
        let move = try XCTUnwrap(v?["move"] as? String)
        let after = try await Core.shared.decode(Snapshot.self, "play", ["moves": ["e2e4"], "move": move])
        XCTAssertEqual(after.moves.count, 2)
    }

    /// An engine whose worker can't start fails the call quickly; it never leaves the game waiting.
    func testABrokenEngineFailsInsteadOfHanging() async throws {
        Core.shared.boot()
        let m = Manifest(id: "broken", name: "Broken", version: "1", files: [], entry: "missing.js")
        let e = Engine(manifest: m, bundled: false, installed: true)
        let began = Date()
        do {
            _ = try await Core.shared.call("think", ["engine": e.coreArgs, "moves": ["e2e4"], "level": 3, "seed": 1])
            XCTFail("a missing engine should fail")
        } catch {}
        XCTAssertLessThan(Date().timeIntervalSince(began), 10)
        // And the bundled engine still plays after it.
        let lite = try XCTUnwrap(Shelf.shared.engine(Shelf.bundledID))
        let v = try await Core.shared.call("think", ["engine": lite.coreArgs, "moves": ["e2e4"], "level": 3, "seed": 1]) as? [String: Any]
        XCTAssertNotNil(v?["move"] as? String)
    }

    /// The web view's block on every web address compiles (a rule list that fails to compile blocks nothing).
    func testTheOfflineRuleCompiles() async throws {
        let list = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "zchess-offline-test", encodedContentRuleList: Core.offline)
        XCTAssertNotNil(list)
    }

    func testRecoversWhenTheWebViewGoesAway() async throws {
        Core.shared.boot()
        _ = try await Core.shared.call("ping")
        let before = Core.shared.generation
        Core.shared.simulateCrash()
        XCTAssertGreaterThan(Core.shared.generation, before)
        let s = try await Core.shared.decode(Snapshot.self, "state", ["moves": ["d2d4"]])
        XCTAssertEqual(s.moves, ["d2d4"])
    }
}

final class PieceSetTests: XCTestCase {
    func testEverySetHasAllTwelvePieces() {
        XCTAssertGreaterThanOrEqual(PieceSets.all.count, 2, "core/piece-sets.json is read")
        XCTAssertTrue(PieceSets.all.contains { $0.id == PieceSets.file.default })
        for set in PieceSets.all {
            for piece in ["wK", "wQ", "wR", "wB", "wN", "wP", "bK", "bQ", "bR", "bB", "bN", "bP"] {
                let image = UIImage(named: PieceSets.image(piece, set: set.id))
                XCTAssertNotNil(image, "\(set.id) \(piece)")
                XCTAssertEqual(image?.size.width ?? 0, image?.size.height ?? 1, "\(set.id) \(piece) is square")
            }
            XCTAssertFalse(set.name.contains(" "), "a set's name is one word")
            XCTAssertNotNil(URL(string: set.source))
            XCTAssertFalse(set.license.isEmpty)
        }
    }

    func testAnUnknownSetFallsBackToTheDefault() {
        XCTAssertEqual(PieceSets.named("nothing").id, PieceSets.file.default)
        XCTAssertEqual(PieceSets.image("wK", set: "nothing"), "\(PieceSets.file.default)/wK")
    }

    @MainActor func testAnEngineResignsOnlyInHumanModeAndOnlyWhenBadlyBeaten() {
        let lost = [-950, -1200, -10000, -900, -2000]
        XCTAssertFalse(GameModel.gaveUp(lost, humanMode: false))
        XCTAssertTrue(GameModel.gaveUp(lost, humanMode: true))
        XCTAssertFalse(GameModel.gaveUp(Array(lost.dropFirst()), humanMode: true), "not yet five searches")
        XCTAssertFalse(GameModel.gaveUp([-950, -1200, -600, -900, -2000], humanMode: true), "merely behind once")
        XCTAssertTrue(GameModel.gaveUp([300, 0] + lost, humanMode: true))
        // Before that, well behind, it asks for a draw: once a game, and never without human mode.
        XCTAssertTrue(GameModel.asksForDraw([0, -520, -600, -700], humanMode: true, asked: false))
        XCTAssertFalse(GameModel.asksForDraw([0, -520, -600, -700], humanMode: true, asked: true))
        XCTAssertFalse(GameModel.asksForDraw([0, -520, -600, -700], humanMode: false, asked: false))
        XCTAssertFalse(GameModel.asksForDraw([-520, -300, -700], humanMode: true, asked: false))
    }
}
