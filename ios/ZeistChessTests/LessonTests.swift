import XCTest
@testable import ZeistChess

/// The fixture lessons in this folder (Fixtures/lessons), read by path: the format as docs/LESSONS.md gives it,
/// independent of the lessons core/lessons ships.
enum LessonFixtures {
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/lessons", directoryHint: .isDirectory)
}

/// The reader: every step kind, and what leaves a lesson out.
final class LessonDataTests: XCTestCase {
    private func lesson(steps: String, extra: String = "") throws -> Lesson {
        try LessonData.lesson(Data("""
        {"id":"tactics-x","course":"tactics","title":"T","line":"L.","side":"w","summary":"S.",\(extra)"steps":[\(steps)]}
        """.utf8))
    }
    private let fen = "\"fen\":\"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1\""

    func testShow() throws {
        let l = try lesson(steps: #"{"type":"show",\#(fen),"text":"Look.","marks":{"squares":["e4"],"arrows":[["e2","e4"]]},"play":["e2e4","e7e5"]}"#)
        let s = l.steps[0]
        XCTAssertEqual(s.kind, .show)
        XCTAssertEqual(s.play, ["e2e4", "e7e5"])
        XCTAssertEqual(s.marks, LessonMarks(squares: ["e4"], arrows: [["e2", "e4"]]))
        XCTAssertNil(l.practice)
    }

    func testMoveWithOneReplyAndWithEach() throws {
        let one = try lesson(steps: #"{"type":"move",\#(fen),"text":"Go.","accept":["e2e4","d2d4"],"reply":"g8f6","wrong":{"a2a3":"No."},"hint":"H.","after":"A.","wins":3,"mate":false,"taught":true}"#)
        XCTAssertEqual(one.steps[0].reply, ["e2e4": "g8f6", "d2d4": "g8f6"], "one reply answers every accepted move")
        XCTAssertEqual(one.steps[0].wrong, ["a2a3": "No."])
        XCTAssertEqual(one.steps[0].hint, "H.")
        XCTAssertEqual(one.steps[0].after, "A.")
        let each = try lesson(steps: #"{"type":"move",\#(fen),"text":"Go.","accept":["e2e4","d2d4"],"reply":{"e2e4":"e7e5","d2d4":"d7d5"}}"#)
        XCTAssertEqual(each.steps[0].reply, ["e2e4": "e7e5", "d2d4": "d7d5"])
    }

    func testPickAndPractice() throws {
        let l = try lesson(steps: #"{"type":"pick",\#(fen),"text":"Tap.","accept":["b1","g1"],"all":true,"wrong":{"c1":"Bishop."},"side":"b"}"#,
                           extra: #""practice":{"fen":"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1","side":"b"},"#)
        let s = l.steps[0]
        XCTAssertEqual(s.kind, .pick)
        XCTAssertEqual(s.accept, ["b1", "g1"])
        XCTAssertTrue(s.all)
        XCTAssertEqual(s.side, "b")
        XCTAssertEqual(s.wrong, ["c1": "Bishop."])
        XCTAssertEqual(l.practice?.side, "b")
    }

    func testFaultsLeaveTheLessonOut() {
        let bad = [
            #"{"type":"move",\#(fen),"text":"Go.","accept":["e2e9"]}"#,                  // not UCI
            #"{"type":"move",\#(fen),"text":"Go.","accept":[]}"#,                        // nothing to accept
            #"{"type":"move",\#(fen),"text":"Go.","accept":["e2e4"],"reply":{"d2d4":"e7e5"}}"#, // a reply to a move not accepted
            #"{"type":"pick",\#(fen),"text":"Tap.","accept":["z9"]}"#,                   // not a square
            #"{"type":"pick",\#(fen),"text":"Tap.","accept":["e4"],"all":"yes"}"#,       // not a boolean
            #"{"type":"show",\#(fen),"text":"Look.","accept":["e2e4"]}"#,                // accept on a show step
            #"{"type":"show","text":"Look."}"#,                                          // the first step has no fen
            #"{"type":"dance",\#(fen),"text":"Look."}"#,                                  // unknown kind
            #"{"type":"show",\#(fen),"text":""}"#,                                       // no text
            #"{"type":"show","fen":"8/8/8 w - - 0 1","text":"Look."}"#,                  // not a FEN
            #"{"type":"show",\#(fen),"text":"Look.","marks":{"arrows":[["e2","e2"]]}}"#, // an arrow to itself
            #"{"type":"move",\#(fen),"text":"Go.","accept":["e2e4"],"wins":"3"}"#,       // a claim of the wrong kind
        ]
        for (n, s) in bad.enumerated() { XCTAssertThrowsError(try lesson(steps: s), "case \(n)") }
        XCTAssertThrowsError(try LessonData.lesson(Data("not json".utf8)))
        XCTAssertThrowsError(try LessonData.lesson(Data(#"{"id":"x","course":"tactics"}"#.utf8)), "an id outside its course")
        XCTAssertNoThrow(try lesson(steps: #"{"type":"show",\#(fen),"text":"Look.","later":1}"#), "an unknown field is ignored")
        XCTAssertNoThrow(try lesson(steps: #"{"type":"move",\#(fen),"text":"Go.","accept":["e2e4"],"sacrifice":true}"#), "sacrifice reads")
    }

    @MainActor func testFEN() {
        XCTAssertTrue(LessonData.isFEN(GameModel.standardStart))
        XCTAssertFalse(LessonData.isFEN("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP w"))
        XCTAssertFalse(LessonData.isFEN("rnbqkbnr/pppppppp/9/8/8/8/PPPPPPPP/RNBQKBNR w"))
        XCTAssertFalse(LessonData.isFEN("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR x"))
    }

    /// The fixtures read whole, in the index's order; a lesson that fails is left out of its chapter, never fatal.
    @MainActor func testTheLibrary() throws {
        let lib = LessonLibrary(folder: LessonFixtures.folder)
        lib.load()
        XCTAssertEqual(lib.faults, [])
        XCTAssertEqual(lib.courses.map(\.id), ["openings", "checkmates"])
        XCTAssertEqual(lib.course("openings")?.lessonCount, 3)
        XCTAssertEqual(lib.next(after: "openings-three-rules")?.id, "openings-italian-ideas")
        XCTAssertNil(lib.next(after: "openings-sicilian-ideas"), "nothing after the last lesson of a course")
        let italian = lib.course("openings")?.chapters.first { $0.id == "italian-game" }
        XCTAssertEqual(italian?.play, ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4"])
        XCTAssertEqual(italian?.group, "With the king's pawn")
        XCTAssertNotNil(italian?.line)
        XCTAssertFalse(italian?.isBlack ?? true)
        XCTAssertTrue(lib.course("openings")?.chapters.first { $0.id == "sicilian-defense" }?.isBlack ?? false)
        XCTAssertNil(lib.next(after: "checkmates-scholars-mate"))

        // A copy with one lesson broken and one missing: both left out, and a chapter left empty is dropped.
        let tmp = FileManager.default.temporaryDirectory.appending(path: "lessons-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: LessonFixtures.folder, to: tmp)
        try Data("{".utf8).write(to: tmp.appending(path: "openings/openings-three-rules.json"))
        try FileManager.default.removeItem(at: tmp.appending(path: "checkmates/checkmates-scholars-mate.json"))
        let broken = LessonLibrary(folder: tmp)
        broken.load()
        XCTAssertEqual(broken.faults.count, 2)
        XCTAssertEqual(broken.courses.map(\.id), ["openings"])
        XCTAssertEqual(broken.course("openings")?.chapters.map(\.id), ["italian-game", "sicilian-defense"])
        XCTAssertNil(broken.lesson("openings-three-rules"))
        let none = LessonLibrary(folder: tmp.appending(path: "nowhere"))
        none.load()
        XCTAssertTrue(none.courses.isEmpty, "no index, no lessons")
        XCTAssertEqual(none.faults.count, 1)
    }

    func testProgressKeeps() {
        let d = UserDefaults(suiteName: "learn-progress-\(UUID())")!
        var p = LearnProgress()
        p.finished = ["a"]
        p.current = .init(id: "b", step: 2)
        p.save(d)
        XCTAssertEqual(LearnProgress.load(d), p)
        d.set(Data("junk".utf8), forKey: LearnProgress.key)
        XCTAssertEqual(LearnProgress.load(d), LearnProgress())
    }
}

/// Playing steps, through core's real rules, with no pauses.
@MainActor
final class LessonModelTests: XCTestCase {
    var store: LearnStore!
    var lib: LessonLibrary!

    override func setUp() async throws {
        Core.shared.boot()
        store = LearnStore(defaults: UserDefaults(suiteName: "lesson-model-\(UUID())")!)
        lib = LessonLibrary(folder: LessonFixtures.folder)
    }

    private func model(_ id: String) -> LessonModel { LessonModel(lesson: lib.lesson(id)!, store: store, pace: 0) }

    func testShowThenAcceptWithReply() async {
        let m = model("checkmates-scholars-mate")
        await m.start()
        XCTAssertEqual(m.index, 0)
        XCTAssertEqual(m.phase, .solved, "a show step is read, then Next")
        XCTAssertEqual(m.marks?.rings, [Square.index("f7")!])
        await m.next()
        XCTAssertEqual(m.index, 1)
        XCTAssertEqual(m.phase, .ready)
        XCTAssertEqual(m.line, "White to move.")
        XCTAssertEqual(m.snap.fen, "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2", "continues from the step before")
        await m.attempt("f1c4")
        XCTAssertEqual(m.index, 2, "the right move and its reply, then the next step by itself")
        XCTAssertEqual(m.line, "The bishop on c4 looks straight at f7.", "the after line stays under the board")
        XCTAssertTrue(m.carried)
        XCTAssertEqual(m.snap.fen, "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/8/PPPP1PPP/RNBQK1NR w KQkq - 2 3")
        XCTAssertEqual(m.marks?.arrows, [BoardMarks.Arrow(from: Square.index("c4")!, to: Square.index("f7")!)])
        m.tap(Square.index("a2")!)
        XCTAssertEqual(m.line, "White to move.", "it gives way when the player taps")
        await m.back()
        XCTAssertEqual(m.index, 1)
        XCTAssertEqual(m.phase, .solved, "Back returns to the step as it was solved")
        XCTAssertEqual(m.played, ["f1c4", "b8c6"])
        XCTAssertEqual(m.line, "The bishop on c4 looks straight at f7.")
        await m.next()
        XCTAssertEqual(m.index, 2)
    }

    func testWrongMovesGoBackWithTheirLine() async {
        let m = model("checkmates-scholars-mate")
        await m.start(at: 1)
        let before = m.snap.board
        await m.attempt("d1h5")
        XCTAssertEqual(m.phase, .ready)
        XCTAssertEqual(m.snap.board, before, "the piece went back")
        XCTAssertEqual(m.line, "The queen aims at f7 too, but out this early she is easy to chase. Bring the bishop out first.")
        await m.attempt("a2a3")
        XCTAssertEqual(m.line, LessonModel.neutral)
        XCTAssertEqual(m.played, [])
    }

    func testHintThenTheMove() async {
        let m = model("checkmates-scholars-mate")
        await m.start(at: 1)
        XCTAssertNil(m.hint)
        m.useHint()
        XCTAssertEqual(m.line, "The bishop on f1 can reach a square on the same diagonal as f7.")
        XCTAssertEqual(m.marks?.lit, [Square.index("f1")!], "the first tap lights the piece to move")
        XCTAssertNil(m.hint)
        m.useHint()
        XCTAssertEqual(m.marks?.lit, [], "then the arrow takes over")
        XCTAssertEqual(m.hint?.from, Square.index("f1"))
        XCTAssertEqual(m.hint?.to, Square.index("c4"))
        XCTAssertFalse(m.canHint)
    }

    func testMarksStayThroughTheStep() async {
        let m = model("checkmates-scholars-mate")
        m.voiceOver = { true }
        await m.start(at: 2)
        let rings = m.marks?.rings
        XCTAssertEqual(rings, [Square.index("f7")!])
        await m.attempt("d1f3")
        XCTAssertEqual(m.marks?.rings, rings, "a wrong try leaves the marks")
        await m.attempt("d1h5")
        XCTAssertEqual(m.phase, .solved)
        XCTAssertEqual(m.marks?.rings, rings, "the right move too, while the step is open")
        await m.next()
        XCTAssertEqual(m.marks?.rings, [], "the next step has its own")
    }

    func testVoiceOverWaitsForNext() async {
        let m = model("checkmates-scholars-mate")
        m.voiceOver = { true }
        await m.start(at: 1)
        await m.attempt("f1c4")
        try? await Task.sleep(for: .seconds(0.2))
        XCTAssertEqual(m.index, 1, "no moving on by itself")
        XCTAssertEqual(m.phase, .solved)
        XCTAssertEqual(m.line, "The bishop on c4 looks straight at f7.")
        await m.next()
        XCTAssertEqual(m.index, 2)
    }

    func testReduceMotionKeepsTheTimeToRead() {
        XCTAssertEqual(LessonModel.delay(1.0, pace: 1), 1.0, "pauses keep their length")
        XCTAssertEqual(LessonModel.delay(0.5, pace: 1), 0.5)
        XCTAssertEqual(LessonModel.delay(1.0, pace: 0), 0)
    }

    func testAlsoGoesBackWithItsLine() async {
        let m = model("checkmates-scholars-mate")
        await m.start(at: 4)
        let before = m.snap.board
        await m.attempt("d8e7")
        XCTAssertEqual(m.phase, .ready)
        XCTAssertEqual(m.snap.board, before)
        XCTAssertEqual(m.line, "That guards f7 too. This lesson goes on with g6.")
        await m.attempt("g7g6")
        XCTAssertEqual(m.index, 5)
    }

    func testAContinuingStepKeepsTheLastMoveTint() async {
        let m = model("checkmates-scholars-mate")
        await m.start(at: 1)
        await m.attempt("f1c4")
        XCTAssertEqual(m.index, 2)
        XCTAssertEqual(m.shownLast, "b8c6", "the reply keeps its tint on the next step")
        let resumed = model("openings-italian-ideas")
        await resumed.start(at: 2)
        XCTAssertEqual(resumed.shownLast, "f1c4", "also when worked out on resuming")
        let fresh = model("checkmates-scholars-mate")
        await fresh.start(at: 4)
        XCTAssertNil(fresh.shownLast, "a step with its own position starts clean")
    }

    func testNextOnAnUnsolvedMovePlaysTheFirstAcceptedMove() async {
        let m = model("checkmates-scholars-mate")
        await m.start(at: 3)
        XCTAssertTrue(m.nextShows)
        await m.next()
        XCTAssertEqual(m.line, "Checkmate. The bishop guards the queen, and the king has no square.")
        XCTAssertEqual(m.index, 4, "played, then on to the next step")
        XCTAssertEqual(m.snap.fen, "r1bqkbnr/pppp1ppp/2n5/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 3 3", "a step with a fen starts there")
        XCTAssertFalse(m.whiteAtBottom, "the step's side")
        await m.back()
        XCTAssertEqual(m.snap.outcome?.reason, "checkmate", "the mate is there going back")
    }

    func testOtherAcceptedMoveAndItsOwnReplyCarryOn() async {
        let m = model("openings-three-rules")
        await m.start(at: 1)
        await m.attempt("d2d4")
        XCTAssertEqual(m.index, 2)
        await m.back()
        XCTAssertEqual(m.played, ["d2d4", "d7d5"], "the reply for this move")
        await m.next()
        XCTAssertEqual(m.snap.fen, "rnbqkbnr/ppp1pppp/8/3p4/3P4/8/PPP1PPPP/RNBQKBNR w KQkq - 0 2", "the next step goes on from what was played")
    }

    func testPickWithAll() async {
        let m = model("openings-three-rules")
        await m.start(at: 2)
        XCTAssertEqual(m.phase, .ready)
        m.pick("c1")
        XCTAssertEqual(m.line, "That is a bishop. The knights stand next to the rooks.")
        m.pick("e4")
        XCTAssertEqual(m.line, LessonModel.neutralSquare)
        m.pick("b1")
        XCTAssertEqual(m.phase, .ready, "every one must be found")
        XCTAssertEqual(m.marks?.lit, [Square.index("b1")!])
        m.tap(Square.index("g1")!)
        XCTAssertEqual(m.phase, .solved)
        XCTAssertEqual(m.line, "Each knight has a square toward the center.")
    }

    func testHintOnAPickWithoutWordsLightsTheAnswers() async {
        let m = model("openings-three-rules")
        await m.start(at: 2)
        m.useHint()
        XCTAssertEqual(Set(m.marks?.rings ?? []), [Square.index("b1")!, Square.index("g1")!])
        XCTAssertFalse(m.canHint)
        XCTAssertEqual(m.phase, .ready, "the player still taps them")
    }

    func testNextOnAnUnsolvedPickLightsTheAnswers() async {
        let m = model("openings-italian-ideas")
        await m.start(at: 3)
        XCTAssertEqual(m.snap.fen, "r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/2P2N2/PP1P1PPP/RNBQK2R b KQkq - 0 4", "worked out through the steps before")
        XCTAssertTrue(m.whiteAtBottom)
        await m.next()
        XCTAssertEqual(m.phase, .ended, "the answers lit on the last step, then the end")
        XCTAssertTrue(store.isFinished("openings-italian-ideas"))
    }

    func testShowPlaysItsLine() async {
        let m = model("openings-italian-ideas")
        await m.start()
        XCTAssertEqual(m.played, ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4"])
        XCTAssertEqual(m.phase, .solved)
        await m.next()
        XCTAssertEqual(m.snap.fen, "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3")
    }

    func testBackAndResume() async {
        let m = model("checkmates-scholars-mate")
        await m.start(at: 2)
        XCTAssertEqual(store.progress.current, .init(id: "checkmates-scholars-mate", step: 2))
        await m.back()
        XCTAssertEqual(m.index, 1)
        XCTAssertEqual(m.phase, .ready)
        XCTAssertEqual(store.progress.current?.step, 1)
        let again = model("checkmates-scholars-mate")
        await again.start()
        XCTAssertEqual(again.index, 1, "leaving and coming back resumes at the step in hand")
        let other = model("openings-three-rules")
        await other.start()
        XCTAssertEqual(other.index, 0, "another lesson starts at its beginning")
    }

    func testFinishing() async {
        let m = model("openings-italian-ideas")
        await m.start(at: 3)
        m.pick("d4")
        await m.next()
        XCTAssertEqual(m.phase, .ended)
        XCTAssertTrue(store.isFinished("openings-italian-ideas"))
        XCTAssertNil(store.progress.current, "a finished lesson is no longer in hand")
    }

    /// Every lesson, played through by its first accepted moves with the app's own rules (core's state call, which
    /// refuses an illegal move), and every accepted move, wrong move and reply tried where it is played.
    func testEveryLessonPlaysThrough() async throws {
        // The shipped lessons must be in the app: as many as the bundled index lists, every one reading.
        let shipped = Places.core.appending(path: "lessons", directoryHint: .isDirectory)
        let raw = try Data(contentsOf: shipped.appending(path: "index.json"))
        let listed = ((try JSONSerialization.jsonObject(with: raw) as? [String: Any])?["courses"] as? [[String: Any]] ?? [])
            .flatMap { ($0["chapters"] as? [[String: Any]]) ?? [] }.flatMap { ($0["lessons"] as? [Any]) ?? [] }.count
        XCTAssertGreaterThan(listed, 0, "the bundled index lists lessons")
        let app = LessonLibrary(folder: shipped)
        XCTAssertEqual(app.courses.reduce(0) { $0 + $1.lessonCount }, listed, "every listed lesson reads: \(app.faults)")
        var folders = [LessonFixtures.folder, shipped]
        // Lessons being written, before they ship: TEST_RUNNER_LESSONS_DIR=<folder with an index.json>.
        if let extra = ProcessInfo.processInfo.environment["LESSONS_DIR"] { folders.append(URL(fileURLWithPath: extra, isDirectory: true)) }
        for folder in folders {
            let lib = LessonLibrary(folder: folder)
            lib.load()
            XCTAssertEqual(lib.faults, [], "\(folder.lastPathComponent): every listed lesson reads")
            XCTAssertFalse(lib.courses.isEmpty)
            for course in lib.courses {
                for entry in course.entries {
                    let l = try XCTUnwrap(lib.lesson(entry.id))
                    try await Self.playThrough(l)
                }
            }
        }
    }

    static func playThrough(_ l: Lesson) async throws {
        let rules = PuzzleModel.coreRules
        var fen = ""
        for (n, s) in l.steps.enumerated() {
            let at = "\(l.id) step \(n + 1)"
            if let f = s.fen { fen = f }
            let here: Snapshot
            do { here = try await rules(fen, []) } catch { XCTFail("\(at): the position is refused: \(fen)"); return }
            switch s.kind {
            case .move:
                for m in s.accept + s.wrong.keys + s.also.keys {
                    do { _ = try await rules(fen, [m]) } catch { XCTFail("\(at): \(m) is illegal") }
                }
                for (m, r) in s.reply {
                    do { _ = try await rules(fen, [m, r]) } catch { XCTFail("\(at): the reply \(r) to \(m) is illegal") }
                }
                XCTAssertNil(here.outcome, "\(at): the game is already over")
            case .pick, .show: break
            }
            let line = LessonModel.line(of: s)
            do { fen = line.isEmpty ? fen : try await rules(fen, line).fen } catch { XCTFail("\(at): \(line) is illegal"); return }
        }
        if let p = l.practice {
            let s = try await rules(p.fen, [])
            XCTAssertNil(s.outcome, "\(l.id): practice starts in a game that is over")
        }
    }
}
