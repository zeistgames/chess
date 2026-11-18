import SwiftUI

/// Learn: a quiet list. The lesson in hand first, when there is one, then the courses that have lessons, each with
/// its line, how many lessons it has and how many are finished. Nothing is locked, dimmed or marked as coming.
struct LearnScreen: View {
    @Binding var path: [Route]
    @State private var store = LearnStore.shared
    private let library = LessonLibrary.shared
    @Environment(\.horizontalSizeClass) private var size

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if let c = store.progress.current, !store.isFinished(c.id), let l = library.lesson(c.id), let e = library.entry(c.id) {
                    ContinueCard(lesson: l, entry: e, step: c.step, course: library.course(l.course)?.title ?? "") {
                        path.append(.lesson(l.id))
                    }
                    .padding(.top, 14).padding(.bottom, 6)
                }
                LearnPlayEntry(path: $path).padding(.top, 14).padding(.bottom, 8)
                if library.courses.isEmpty {
                    Text("No lessons could be read.").font(Z.text(15)).foregroundStyle(Z.soft).padding(.top, 24)
                }
                ForEach(Array(library.courses.enumerated()), id: \.element.id) { n, c in
                    if n > 0 { Rectangle().fill(Z.hair).frame(height: 1) }
                    CourseRow(course: c, finished: store.finishedCount(c.entries.map(\.id))) { path.append(.course(c.id)) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Z.ground.ignoresSafeArea())
        .foregroundStyle(Z.ink)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack {
            Text("Learn").font(Z.title(32, relativeTo: .title)).accessibilityAddTraits(.isHeader)
            Spacer()
            ProfileButton()
        }
        .padding(.top, 6)
    }
}

/// The lesson in hand: its title, its course and step, the steps as quiet bars, and its small board.
struct ContinueCard: View {
    let lesson: Lesson
    let entry: LessonIndex.Entry
    let step: Int
    let course: String
    let action: () -> Void

    var body: some View {
        Button { Feel.shared.select(); action() } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Continue").font(Z.medium(11, relativeTo: .caption)).tracking(1.4).textCase(.uppercase).foregroundStyle(Z.lesson)
                    Text(lesson.title).font(Z.title(21, relativeTo: .title3)).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                    Text("\(course) · step \(step + 1) of \(lesson.steps.count)").font(Z.text(13)).foregroundStyle(Z.soft).padding(.top, 4)
                    HStack(spacing: 5) {
                        ForEach(0..<lesson.steps.count, id: \.self) { i in
                            Capsule().fill(Z.ink.opacity(i <= step ? 0.7 : 0.18)).frame(width: 16, height: 3)
                        }
                    }
                    .padding(.top, 9)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                MiniBoard(entry: entry, size: 96, radius: 9)
            }
            .padding(14)
            .card(26)
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(Press())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Continue. \(lesson.title). \(course), step \(step + 1) of \(lesson.steps.count).")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("learn-continue")
    }
}

/// A course in Learn's list: its name and line, the number of lessons and how many are finished.
struct CourseRow: View {
    let course: LessonIndex.Course
    let finished: Int
    let action: () -> Void

    var body: some View {
        Button { Feel.shared.select(); action() } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(course.title).font(Z.title(23, relativeTo: .title2)).lineLimit(1).minimumScaleFactor(0.8)
                    Text(course.line).font(Z.text(14)).foregroundStyle(Z.soft).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(course.lessonCount)").font(Z.medium(15)).monospacedDigit()
                    Text(finished > 0 ? "\(finished) finished" : course.lessonCount == 1 ? "lesson" : "lessons")
                        .font(Z.text(12.5)).foregroundStyle(Z.dim).lineLimit(1).fixedSize()
                }
                Chevron()
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(Press())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(course.title). \(course.line) \(Plural.lessons(course.lessonCount))\(finished > 0 ? ", \(finished) finished" : "").")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("course-\(course.id)")
    }
}

struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right").font(.system(size: 14, weight: .medium)).foregroundStyle(Z.dim).accessibilityHidden(true)
    }
}

enum Plural {
    static func lessons(_ n: Int) -> String { n == 1 ? "1 lesson" : "\(n) lessons" }
}
