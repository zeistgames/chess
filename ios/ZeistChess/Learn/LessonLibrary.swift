import Foundation
import Observation

/// The lessons in the app (core/lessons, bundled by scripts/bundle-core.sh), read once on first use. Only what reads
/// is listed: a lesson whose file is missing or does not read is left out (and logged), a chapter left with no
/// lessons is dropped, and so is a course. Nothing is ever shown as locked or coming. Not observed: once read,
/// nothing in it changes, so reading it from a view's body is safe.
@MainActor
final class LessonLibrary {
    static let shared = LessonLibrary(folder: LessonLibrary.bundledFolder)

    static var bundledFolder: URL {
        #if DEBUG
        // UI tests and screenshots point the app at a folder of their own (-lessons <folder>).
        if let f = Debug.value("-lessons") { return URL(fileURLWithPath: f, isDirectory: true) }
        #endif
        return Places.core.appending(path: "lessons", directoryHint: .isDirectory)
    }

    let folder: URL
    /// The courses that have lessons, read on first use.
    var courses: [LessonIndex.Course] { load(); return read }
    private var read: [LessonIndex.Course] = []
    private var lessons: [String: Lesson] = [:]
    /// Lessons left out, with why: for tests and the log.
    private(set) var faults: [String] = []
    private var loaded = false

    init(folder: URL) { self.folder = folder }

    func load() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: folder.appending(path: "index.json")) else {
            fault("index.json is missing")
            return
        }
        let index: LessonIndex
        do { index = try LessonData.index(data) } catch {
            fault("index.json: \(error)")
            return
        }
        var seen = Set<String>()
        for var course in index.courses {
            for c in course.chapters.indices {
                course.chapters[c].lessons = course.chapters[c].lessons.filter { entry in
                    guard seen.insert(entry.id).inserted else { fault("\(entry.id): listed twice"); return false }
                    let file = folder.appending(path: "\(course.id)/\(entry.id).json")
                    do {
                        let l = try LessonData.lesson(try Data(contentsOf: file))
                        guard l.id == entry.id, l.course == course.id else { fault("\(entry.id): the file names another lesson or course"); return false }
                        if l.title != entry.title || l.line != entry.line { LessonData.log.notice("\(entry.id, privacy: .public): title or line differs from the index") }
                        lessons[l.id] = l
                        return true
                    } catch {
                        fault("\(entry.id): \(error)")
                        return false
                    }
                }
            }
            course.chapters.removeAll { $0.lessons.isEmpty }
            if !course.chapters.isEmpty { read.append(course) }
        }
    }

    private func fault(_ s: String) {
        faults.append(s)
        LessonData.log.error("left out: \(s, privacy: .public)")
    }

    func course(_ id: String) -> LessonIndex.Course? { courses.first { $0.id == id } }
    func lesson(_ id: String) -> Lesson? { load(); return lessons[id] }
    func entry(_ id: String) -> LessonIndex.Entry? {
        lesson(id).flatMap { l in course(l.course)?.entries.first { $0.id == id } }
    }

    /// The lesson after this one in its course, or nil at the end of the course.
    func next(after id: String) -> LessonIndex.Entry? {
        guard let l = lesson(id), let entries = course(l.course)?.entries, let i = entries.firstIndex(where: { $0.id == id }),
              i + 1 < entries.count else { return nil }
        return entries[i + 1]
    }
}

/// What the player has done in Learn, kept on this device: the lessons finished, and the lesson and step in hand.
/// Nothing else: no streaks, scores or times.
struct LearnProgress: Codable, Equatable {
    var finished: Set<String> = []
    var current: Current?

    struct Current: Codable, Equatable {
        var id: String
        var step: Int
    }

    static let key = "learn.progress"

    static func load(_ defaults: UserDefaults = .standard) -> LearnProgress {
        guard let d = defaults.data(forKey: key), let p = try? JSONDecoder().decode(LearnProgress.self, from: d) else { return LearnProgress() }
        return p
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let d = try? JSONEncoder().encode(self) { defaults.set(d, forKey: Self.key) }
    }
}

/// The progress, shared by Learn's pages and the lesson being played, saved as it changes.
@MainActor @Observable
final class LearnStore {
    static let shared = LearnStore()

    private(set) var progress: LearnProgress
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        progress = LearnProgress.load(defaults)
    }

    func isFinished(_ id: String) -> Bool { progress.finished.contains(id) }
    func finishedCount(_ ids: [String]) -> Int { ids.reduce(0) { $0 + (progress.finished.contains($1) ? 1 : 0) } }

    /// The lesson and step in hand.
    func at(_ id: String, step: Int) {
        let c = LearnProgress.Current(id: id, step: step)
        guard progress.current != c else { return }
        progress.current = c
        progress.save(defaults)
    }

    func finish(_ id: String) {
        progress.finished.insert(id)
        if progress.current?.id == id { progress.current = nil }
        progress.save(defaults)
    }

    /// Re-reads what is saved (after -reset, and in tests).
    func reload() { progress = LearnProgress.load(defaults) }
}
