import SwiftUI

/// A lesson: its course and title at the top, quiet dots for the steps, the step's words, the board (the same board
/// as Play and Puzzles), a line under it, and a glass bar with Back, Hint and Next. At the end: what it taught, the
/// way to practice from there, the next lesson and the way back to the course. Pushed over the dock.
struct LessonScreen: View {
    let id: String
    @Binding var path: [Route]
    @State private var model: LessonModel?
    private let library = LessonLibrary.shared

    var body: some View {
        Group {
            if let model { LessonBody(model: model, path: $path) }
            else {
                VStack {
                    LessonTop(course: "", title: "", path: $path)
                    Spacer()
                    if library.lesson(id) == nil { Text("This lesson couldn't be read.").font(Z.text(15)).foregroundStyle(Z.soft) }
                    Spacer()
                }
            }
        }
        .background(Z.ground.ignoresSafeArea())
        .foregroundStyle(Z.ink)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: id) {
            guard model?.lesson.id != id, let l = library.lesson(id) else { return }
            let m = LessonModel(lesson: l)
            model = m
            var step: Int?
            #if DEBUG
            if Debug.value("-lesson") == id { step = Debug.value("-lesson-step").flatMap { $0 == "last" ? l.steps.count - 1 : Int($0) } }
            #endif
            await m.start(at: step)
        }
    }
}

private struct LessonBody: View {
    let model: LessonModel
    @Binding var path: [Route]
    @AppStorage(Look.edgeKey) private var edge = false
    @Environment(\.horizontalSizeClass) private var size
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    private let library = LessonLibrary.shared

    private var gutter: CGFloat { size == .regular ? 40 : 14 }
    private var flush: Bool { edge && size != .regular }
    private var courseTitle: String { library.course(model.lesson.course)?.title ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            LessonTop(course: courseTitle, title: model.lesson.title, path: $path)
            if model.phase == .ended {
                LessonEnd(model: model, course: courseTitle, path: $path)
            } else {
                dots.padding(.top, 12)
                Spacer(minLength: 6)
                VStack(spacing: 0) {
                    Text(model.step.text)
                        .font(Z.text(17)).lineSpacing(3)
                        .multilineTextAlignment(.center)
                        // Never cut short: where the words don't fit beside the board, they shrink.
                        .minimumScaleFactor(0.45)
                        .frame(maxWidth: .infinity, minHeight: 76)
                        .padding(.horizontal, 24).padding(.bottom, 12)
                        .id(model.index)
                        .transition(.opacity)
                        .accessibilityIdentifier("lesson-text")
                    BoardView(model: model, square: flush)
                        .shadow(color: .black.opacity(flush ? 0 : 0.35), radius: 18, y: 12)
                        .padding(.horizontal, flush ? 0 : gutter)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Board")
                    Text(model.line)
                        .font(Z.text(15)).foregroundStyle(Z.soft)
                        .multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.85)
                        .frame(minHeight: 44, alignment: .top).padding(.horizontal, 28).padding(.top, 12)
                        .contentTransition(.opacity)
                        .animation(.easeOut(duration: 0.2), value: model.line)
                        .accessibilityIdentifier("lesson-status")
                }
                .frame(maxWidth: 720)
                .animation(.easeOut(duration: 0.2), value: model.index)
                Spacer(minLength: 6)
                bar
                    .padding(.horizontal, 16).padding(.bottom, 12)
                    .frame(maxWidth: 720)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { Feel.shared.prepare() }
        // VoiceOver reads the step's words when it opens, and the line under the board when it changes.
        .onChange(of: model.index, initial: true) { _, _ in
            if voiceOver { UIAccessibility.post(notification: .announcement, argument: model.step.text) }
        }
        .onChange(of: model.line) { _, l in
            if voiceOver, !l.isEmpty { UIAccessibility.post(notification: .announcement, argument: l) }
        }
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0..<model.count, id: \.self) { i in
                Circle().fill(Z.ink.opacity(i == model.index ? 1 : i < model.index ? 0.5 : 0.18)).frame(width: 7, height: 7)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(model.index + 1) of \(model.count)")
        .accessibilityIdentifier("lesson-dots")
    }

    private var bar: some View {
        HStack(spacing: 0) {
            DockButton(symbol: "chevron.left", title: "Back", label: "The step before", enabled: model.canBack) {
                Task { await model.back() }
            }
            .accessibilityIdentifier("lesson-back")
            DockButton(symbol: "lightbulb", title: "Hint", label: model.hintLevel == 0 && model.step.hint != nil ? "Hint" : "Show the move", enabled: model.canHint) {
                model.useHint()
            }
            .accessibilityIdentifier("lesson-hint")
            DockButton(symbol: "arrow.right", title: "Next",
                       label: model.nextShows ? (model.step.kind == .pick ? "Show the answer" : "Play the move") : model.isLast ? "Finish the lesson" : "Next step",
                       enabled: model.canNext) {
                Task { await model.next() }
            }
            .background(Capsule().fill(Z.wash.opacity(model.phase == .solved ? 1.6 : 0)).padding(.vertical, 4))
            .accessibilityIdentifier("lesson-next")
        }
        .padding(.horizontal, 8)
        .glassDock()
        .animation(.easeOut(duration: 0.2), value: model.phase == .solved)
    }
}

/// The top of a lesson: back at the left, the course and the title in the middle.
private struct LessonTop: View {
    let course: String
    let title: String
    @Binding var path: [Route]

    var body: some View {
        HStack(spacing: 12) {
            RoundIcon(symbol: "chevron.left", label: "Back to \(course.isEmpty ? "Learn" : course)") { if !path.isEmpty { path.removeLast() } }
                .accessibilityIdentifier("page-back")
            VStack(spacing: 2) {
                Text(course).font(Z.medium(10.5, relativeTo: .caption)).tracking(1.5).textCase(.uppercase).foregroundStyle(Z.dim).lineLimit(1)
                Text(title).font(Z.medium(15)).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }
}

/// The end of a lesson: the position it ended on, "Lesson finished." and what it taught, then practice from there,
/// the next lesson in the course, and the way back.
private struct LessonEnd: View {
    let model: LessonModel
    let course: String
    @Binding var path: [Route]
    @State private var starting = false
    @State private var problem: String?
    @State private var confirming = false
    @AppStorage(Pick.engineKey) private var engineID = Shelf.bundledID
    private let library = LessonLibrary.shared

    private var engine: Engine? {
        Shelf.shared.engine(engineID).flatMap { $0.installed ? $0 : nil } ?? Shelf.shared.engine(Shelf.bundledID)
    }

    var body: some View {
        let l = model.lesson
        let next = library.next(after: l.id)
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    // The practice position when there is one, so "from here" is true; else where the lesson ended.
                    BoardStill(fen: l.practice?.fen ?? model.snap.fen,
                               flipped: l.practice.map { $0.side == "b" } ?? !model.whiteAtBottom,
                               last: l.practice == nil ? model.snap.last : nil)
                        .frame(width: 236, height: 236)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Z.ink.opacity(0.14), lineWidth: 1))
                        .padding(.top, 14)
                    Text("Lesson finished.").font(Z.text(14)).foregroundStyle(Z.dim).padding(.top, 14)
                        .accessibilityIdentifier("lesson-finished")
                    Text(l.summary).font(Z.title(23, relativeTo: .title2)).lineSpacing(4).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24).padding(.top, 18)
                        .accessibilityIdentifier("lesson-summary")
                }
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: 12) {
                if let p = l.practice, let e = engine {
                    Button {
                        // A game in progress on Play would end: ask first.
                        if GameLog.shared.current != nil { confirming = true } else { Task { await practice(p, engine: e) } }
                    } label: {
                        VStack(spacing: 1) {
                            Text(starting ? "Starting" : "Practice against \(e.name) from here").lineLimit(1).minimumScaleFactor(0.8)
                            Text("You play \(p.side == "w" ? "White" : "Black"), at your level").font(Z.text(12)).opacity(0.7)
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(Pill(solid: true, wide: true))
                    .disabled(starting)
                    .accessibilityIdentifier("lesson-practice")
                }
                // The puzzle theme that practices this lesson's idea, where the lesson names one the set has.
                if let id = l.puzzles, let t = PuzzleSet.shared.theme(id) {
                    Button("Puzzles: \(t.name)") { Feel.shared.select(); path.append(.theme(t.id)) }
                        .buttonStyle(Pill(solid: l.practice == nil, wide: true))
                        .accessibilityLabel("Puzzles on \(t.name)")
                        .accessibilityIdentifier("lesson-puzzles")
                }
                if let next {
                    // The title would be cut off on a phone; it is on the course page and is read out by VoiceOver.
                    Button("Next lesson") {
                        Feel.shared.select()
                        if !path.isEmpty { path.removeLast() }
                        path.append(.lesson(next.id))
                    }
                    .buttonStyle(Pill(solid: l.practice == nil && l.puzzles == nil, wide: true))
                    .accessibilityLabel("Next lesson: \(next.title)")
                    .accessibilityIdentifier("lesson-next-lesson")
                }
                if let problem { Text(problem).font(Z.text(14)).foregroundStyle(Z.soft) }
                Button("Back to \(course)") { Feel.shared.select(); backToCourse() }
                    .font(Z.text(15)).foregroundStyle(Z.soft)
                    .frame(minHeight: 44)
                    .buttonStyle(Press())
                    .accessibilityIdentifier("lesson-course")
            }
            .padding(.horizontal, 20).padding(.bottom, 10)
            .frame(maxWidth: 460)
        }
        .transition(.opacity)
        .confirmationDialog("You have a game in progress.", isPresented: $confirming, titleVisibility: .visible) {
            Button("Start practice", role: .destructive) {
                if let p = model.lesson.practice, let e = engine { Task { await practice(p, engine: e) } }
            }
            Button("Keep my game", role: .cancel) {}
        } message: { Text("Starting practice ends it.") }
    }

    /// Back to the course page: the one below this lesson when there is one, else the course is put in its place.
    private func backToCourse() {
        let c = model.lesson.course
        if !path.isEmpty { path.removeLast() }
        switch path.last {
        case .course(let id) where id == c: return
        case .chapter(let id, _) where id == c: return
        default: path.append(.course(c))
        }
    }

    /// An ordinary game on Play from the lesson's position, with the engine chosen on Play, at the player's level,
    /// unrated, with no clock. What Play remembers (its position, side and clock) is left as it was.
    private func practice(_ p: LessonPractice, engine e: Engine) async {
        guard !starting else { return }
        starting = true
        problem = nil
        defer { starting = false }
        let d = UserDefaults.standard
        let manual = d.bool(forKey: Pick.manualKey)
        let level = manual ? (d.object(forKey: Pick.levelKey) as? Int ?? 3) : await GameModel.startingLevel(e.id)
        do {
            let m = try await GameModel.begin(engine: e, player: p.side, level: level, adaptive: !manual, rating: nil, time: nil, start: p.fen)
            Feel.shared.select()
            Session.shared.game = m
            Session.shared.tab = .play
            path = [.game]
        } catch {
            problem = "The game couldn't start. Try again."
            ReviewRequest.shared.record(.trouble)
        }
    }
}
