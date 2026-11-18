import SwiftUI

/// A course: its chapters and their lessons, each with its small board. A long course shows one chapter at a time
/// behind a row of chapter names, so no list runs long; a short one lists every chapter. Openings is grouped by
/// White's first move and then Black's reply, each opening a row that opens its own page. Pushed over the dock.
struct CourseScreen: View {
    let id: String
    @Binding var path: [Route]
    @State private var store = LearnStore.shared
    @State private var chapter: String?
    @State private var blackSide = false
    private let library = LessonLibrary.shared

    /// Beyond this many lessons, a course shows one chapter at a time.
    static let chooseAbove = 12

    var body: some View {
        let course = library.course(id)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageBar(path: $path)
                if let course {
                    Text(course.title).font(Z.title(36, relativeTo: .largeTitle)).accessibilityAddTraits(.isHeader).padding(.top, 8)
                    Text(subtitle(course)).font(Z.text(14.5)).foregroundStyle(Z.soft).padding(.top, 6)
                    if course.id == "openings" { openings(course) } else { chapters(course) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Z.ground.ignoresSafeArea())
        .foregroundStyle(Z.ink)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func subtitle(_ c: LessonIndex.Course) -> String {
        let n = c.lessonCount
        if c.id == "openings" {
            let o = c.chapters.filter { $0.group != nil }.count
            if o > 0 { return "\(o == 1 ? "1 opening" : "\(o) openings and defenses"), \(Plural.lessons(n))." }
        }
        if c.chapters.count > 1 { return "\(c.chapters.count) chapters, \(Plural.lessons(n))." }
        return "\(Plural.lessons(n))."
    }

    // MARK: Chapters

    @ViewBuilder private func chapters(_ c: LessonIndex.Course) -> some View {
        if c.chapters.count > 1, c.lessonCount > Self.chooseAbove {
            let shown = c.chapters.first { $0.id == chapter } ?? c.chapters[0]
            Chips(options: c.chapters.map { ($0.id, $0.title) }, value: Binding(get: { shown.id }, set: { chapter = $0 }))
                .padding(.top, 16).padding(.horizontal, -20)
            LessonList(entries: shown.lessons, path: $path).padding(.top, 6)
        } else {
            ForEach(c.chapters) { ch in
                if c.chapters.count > 1 {
                    SectionLabel(title: ch.title, detail: count(ch)).padding(.top, 24).padding(.bottom, 2)
                }
                LessonList(entries: ch.lessons, path: $path).padding(.top, c.chapters.count > 1 ? 0 : 12)
            }
        }
    }

    private func count(_ ch: LessonIndex.Chapter) -> String {
        let done = store.finishedCount(ch.lessons.map(\.id))
        return done > 0 ? "\(done) of \(ch.lessons.count) finished" : Plural.lessons(ch.lessons.count)
    }

    // MARK: Openings

    /// A group as a heading. Groups are plain words ("With the king's pawn"); an index written before that, in
    /// notation, still reads: "1.e4 e5" becomes "After 1...e5".
    static func heading(_ group: String) -> String {
        let parts = group.split(separator: " ")
        if group.hasSuffix(", other replies"), let m = parts.first { return "Other replies to \(m.dropLast())" }
        if parts.count == 2, parts[0].hasPrefix("1.") { return "After 1...\(parts[1])" }
        return group
    }

    /// Openings by the side that chooses them, As White and As Black, each in the index's groups and order.
    /// No notation here: a row is the position, the name, one plain line and the lessons.
    @ViewBuilder private func openings(_ c: LessonIndex.Course) -> some View {
        let general = c.chapters.filter { $0.group == nil }
        let named = c.chapters.filter { $0.group != nil }
        let sides = [false, true].filter { b in named.contains { $0.isBlack == b } }
        ForEach(general) { ch in
            Button { Feel.shared.select(); path.append(.chapter(c.id, ch.id)) } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ch.title).font(Z.title(19, relativeTo: .title3))
                        let done = store.finishedCount(ch.lessons.map(\.id))
                        Text(done > 0 ? "\(Plural.lessons(ch.lessons.count)) · \(done) finished" : Plural.lessons(ch.lessons.count))
                            .font(Z.text(13)).foregroundStyle(Z.dim)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Chevron()
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .card(20)
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(Press())
            .accessibilityIdentifier("chapter-\(ch.id)")
            .padding(.top, 16)
        }
        if !sides.isEmpty {
            let black = sides.contains(blackSide) ? blackSide : sides[0]
            if sides.count > 1 {
                Choice(options: [(false, "As White"), (true, "As Black")], value: $blackSide)
                    .padding(.top, 18)
                    .accessibilityIdentifier("openings-side")
            }
            let mine = named.filter { $0.isBlack == black }
            let groups = mine.map { $0.group! }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            ForEach(groups, id: \.self) { g in
                let rows = mine.filter { $0.group == g }
                SectionLabel(title: Self.heading(g)).padding(.top, 24).padding(.bottom, 2)
                ForEach(Array(rows.enumerated()), id: \.element.id) { n, ch in
                    if n > 0 { Rectangle().fill(Z.hair).frame(height: 1) }
                    OpeningRow(chapter: ch, finished: store.finishedCount(ch.lessons.map(\.id))) { path.append(.chapter(c.id, ch.id)) }
                }
            }
        }
    }
}

/// A chapter's own page: for an opening, its moves, who it is for and the position it names; then its lessons.
struct ChapterScreen: View {
    let course: String
    let id: String
    @Binding var path: [Route]
    @State private var store = LearnStore.shared
    private let library = LessonLibrary.shared

    var body: some View {
        let ch = library.course(course)?.chapters.first { $0.id == id }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageBar(path: $path)
                if let ch {
                    Text(ch.title).font(Z.title(36, relativeTo: .largeTitle)).accessibilityAddTraits(.isHeader).padding(.top, 8)
                        .fixedSize(horizontal: false, vertical: true)
                    Text([OpeningRow.who(ch.forSide), Plural.lessons(ch.lessons.count)].compactMap { $0 }.joined(separator: " · "))
                        .font(Z.text(13)).foregroundStyle(Z.dim).padding(.top, 6)
                    if let l = ch.line { Text(l).font(Z.text(15)).foregroundStyle(Z.soft).padding(.top, 10).fixedSize(horizontal: false, vertical: true) }
                    if let play = ch.play, !play.isEmpty {
                        OpeningReplay(play: play, moves: ch.moves, flipped: ch.isBlack).padding(.top, 20)
                    } else if let fen = ch.fen {
                        BoardStill(fen: fen, flipped: ch.isBlack, last: nil, coordinates: true)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Z.ink.opacity(0.18), lineWidth: 1))
                            .padding(.top, 20)
                            .padding(.horizontal, -4)
                        if let m = ch.moves { Text(m).font(Z.text(13)).foregroundStyle(Z.dim).padding(.top, 10) }
                    }
                    let done = store.finishedCount(ch.lessons.map(\.id))
                    SectionLabel(title: "Lessons", detail: done > 0 ? "\(done) of \(ch.lessons.count) finished" : "").padding(.top, 26).padding(.bottom, 2)
                    LessonList(entries: ch.lessons, path: $path)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Z.ground.ignoresSafeArea())
        .foregroundStyle(Z.ink)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: Parts

/// The top of a pushed page in Learn: back at the left, the profile button at the right.
struct PageBar: View {
    @Binding var path: [Route]

    var body: some View {
        HStack {
            RoundIcon(symbol: "chevron.left", label: "Back") { if !path.isEmpty { path.removeLast() } }
                .accessibilityIdentifier("page-back")
            Spacer()
            ProfileButton()
        }
        .padding(.top, 6)
    }
}

/// A small label over a list, with a quiet note at the right.
struct SectionLabel: View {
    let title: String
    var detail = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).zLabel()
            Spacer()
            Text(detail).font(Z.text(12)).foregroundStyle(Z.dim)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Chapter names in a row that scrolls sideways; the chosen one is solid.
struct Chips: View {
    let options: [(String, String)]
    @Binding var value: String

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(options, id: \.0) { o in
                    let on = o.0 == value
                    Button { if !on { value = o.0; Feel.shared.select() } } label: {
                        Text(o.1).font(Z.medium(13.5)).lineLimit(1)
                            .foregroundStyle(on ? Z.ground : Z.soft)
                            .padding(.horizontal, 14).frame(minHeight: 40)
                            .background(Capsule().fill(on ? Z.ink : .clear))
                            .overlay(Capsule().strokeBorder(on ? .clear : Z.hair, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(Press())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        // A scroller draws into the safe area beside it; on a screen with a system strip down one side (the closed
        // Duo) the chips would run under the clock.
        .clipped()
    }
}

/// Lessons, one per row, separated by hairlines.
struct LessonList: View {
    let entries: [LessonIndex.Entry]
    @Binding var path: [Route]
    @State private var store = LearnStore.shared

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { n, e in
                if n > 0 { Rectangle().fill(Z.hair).frame(height: 1) }
                LessonRow(entry: e, finished: store.isFinished(e.id)) { path.append(.lesson(e.id)) }
            }
        }
    }
}

/// A lesson in a list: its small board (with a quiet mark when finished), its title and line.
struct LessonRow: View {
    let entry: LessonIndex.Entry
    let finished: Bool
    let action: () -> Void

    var body: some View {
        Button { Feel.shared.select(); action() } label: {
            HStack(spacing: 14) {
                MiniBoard(entry: entry, size: 80, radius: 7)
                    .overlay(alignment: .bottomTrailing) { if finished { FinishedMark().offset(x: 5, y: 5) } }
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title).font(Z.title(18, relativeTo: .headline)).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(entry.line).font(Z.text(12.5)).foregroundStyle(Z.dim).multilineTextAlignment(.leading).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Chevron()
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(Press())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.title). \(entry.line)")
        .accessibilityValue(finished ? "Finished" : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("lesson-\(entry.id)")
    }
}

/// An opening in its group: the position it names (from the side that plays it), its name, one plain line, and
/// its lessons. No notation.
struct OpeningRow: View {
    let chapter: LessonIndex.Chapter
    let finished: Int
    let action: () -> Void

    static func who(_ f: String?) -> String? {
        switch f {
        case "white": "For White"
        case "black": "For Black"
        default: nil
        }
    }

    var body: some View {
        let count = [Plural.lessons(chapter.lessons.count), finished > 0 ? "\(finished) finished" : nil].compactMap { $0 }.joined(separator: " · ")
        Button { Feel.shared.select(); action() } label: {
            HStack(spacing: 14) {
                MiniBoard(fen: chapter.fen ?? chapter.lessons.first?.fen ?? GameModel.standardStart, flipped: chapter.isBlack, size: 80, radius: 7)
                VStack(alignment: .leading, spacing: 3) {
                    Text(chapter.title).font(Z.title(19, relativeTo: .headline)).fixedSize(horizontal: false, vertical: true)
                    if let l = chapter.line {
                        Text(l).font(Z.text(13)).foregroundStyle(Z.soft).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(count).font(Z.text(12.5)).foregroundStyle(Z.dim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Chevron()
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(Press())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(chapter.title). \(chapter.line.map { $0 + " " } ?? "")\(count).")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("chapter-\(chapter.id)")
    }
}

/// A small still board, with a lesson's rings and arrows.
struct MiniBoard: View {
    let fen: String
    var flipped = false
    var last: String? = nil
    var marks: BoardMarks? = nil
    let size: CGFloat
    var radius: CGFloat = 7

    init(fen: String, flipped: Bool = false, last: String? = nil, marks: BoardMarks? = nil, size: CGFloat, radius: CGFloat = 7) {
        self.fen = fen
        self.flipped = flipped
        self.last = last
        self.marks = marks
        self.size = size
        self.radius = radius
    }

    init(entry: LessonIndex.Entry, size: CGFloat, radius: CGFloat = 7) {
        self.init(fen: entry.fen, flipped: entry.side == "b", marks: entry.marks.map { BoardMarks($0) }, size: size, radius: radius)
    }

    var body: some View {
        BoardStill(fen: fen, flipped: flipped, last: last, marks: marks)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Z.ink.opacity(0.12), lineWidth: 1))
    }
}

/// Finished: a small bone disc with a tick.
struct FinishedMark: View {
    var body: some View {
        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Z.ground)
            .frame(width: 20, height: 20)
            .background(Circle().fill(Z.ink))
            .overlay(Circle().strokeBorder(Z.ground, lineWidth: 2).padding(-2))
            .accessibilityHidden(true)
    }
}
