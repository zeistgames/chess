import SwiftUI

/// The puzzle itself, shared by the Puzzles place, a theme and the daily: whose move it is above the board, the
/// board (the same as Play's, honoring edge to edge), and the quiet line under it.
struct PuzzleBoardArea: View {
    let model: PuzzleModel
    /// A smaller board, leaving room below it (the daily's calendar).
    var maxBoard: CGFloat? = nil
    @AppStorage(Look.edgeKey) private var edge = false
    @Environment(\.horizontalSizeClass) private var size
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    private var gutter: CGFloat { size == .regular ? 40 : 14 }
    private var flush: Bool { edge && size != .regular && maxBoard == nil }

    var body: some View {
        VStack(spacing: 0) {
            ask.padding(.bottom, 12).padding(.horizontal, 24)
            BoardView(model: model, square: flush)
                .shadow(color: .black.opacity(flush ? 0 : 0.35), radius: 18, y: 12)
                .frame(maxWidth: maxBoard)
                .padding(.horizontal, flush ? 0 : gutter)
                .opacity(model.phase == .empty ? 0.35 : 1)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Board")
            Text(model.line)
                .font(Z.text(14.5)).foregroundStyle(Z.soft)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 22).padding(.horizontal, 28).padding(.top, 12)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: model.line)
                .accessibilityIdentifier("puzzle-status")
        }
        .overlay(alignment: .topLeading) { PuzzleAnswerHook(model: model) }
        .onChange(of: model.line) { _, l in
            if voiceOver, !l.isEmpty { UIAccessibility.post(notification: .announcement, argument: l) }
        }
    }

    /// Whose move it is, and the goal where the data gives one: "White to move. Mate in two."
    /// On one line where it fits; the goal under it where it doesn't. Never cut short.
    private var ask: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 6) { turn; goal }.fixedSize()
            VStack(spacing: 2) { turn; goal }
        }
        .multilineTextAlignment(.center)
        .frame(minHeight: 24)
        .opacity(model.puzzle == nil ? 0 : model.phase == .done ? 0.4 : 1)
        .animation(.easeOut(duration: 0.2), value: model.phase == .done)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("puzzle-turn")
    }

    private var turn: some View { Text(model.turnLine).font(Z.medium(17, relativeTo: .headline)).fixedSize(horizontal: false, vertical: true) }
    @ViewBuilder private var goal: some View {
        if !model.goalLine.isEmpty { Text(model.goalLine).font(Z.text(15.5)).foregroundStyle(Z.soft).fixedSize(horizontal: false, vertical: true) }
    }
}

/// The puzzle's controls on a screen that shows the dock: plain, part of the page, never a second floating bar.
/// Flip and Retry as round icons at the left, Show the move as quiet words after a miss, Next as a pill at the right.
struct PuzzlePlainControls: View {
    let model: PuzzleModel

    var body: some View {
        HStack(spacing: 10) {
            RoundIcon(symbol: "arrow.up.arrow.down", label: "Flip the board") {
                Feel.shared.select()
                withAnimation(.easeInOut(duration: 0.25)) { model.flipped.toggle() }
            }
            .disabled(model.puzzle == nil)
            .accessibilityIdentifier("puzzle-flip")
            RoundIcon(symbol: "arrow.counterclockwise", label: "Try this puzzle again from the start") { Task { await model.retry() } }
                .disabled(!model.canRetry)
                .opacity(model.canRetry ? 1 : 0.35)
                .accessibilityIdentifier("puzzle-retry")
            if model.canShow {
                Button("Show the move") { Task { await model.showMove() } }
                    .font(Z.text(14.5)).foregroundStyle(Z.soft)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 44)
                    .buttonStyle(Press())
                    .accessibilityIdentifier("puzzle-show")
                    .transition(.opacity)
            }
            Spacer(minLength: 4)
            Button("Next") {
                Feel.shared.select()
                Task { await model.next() }
            }
            .buttonStyle(Pill(solid: model.phase == .done, small: true))
            .disabled(!model.canNext)
            .accessibilityLabel(model.phase == .done ? "Next puzzle" : "Skip to the next puzzle")
            .accessibilityIdentifier("puzzle-next")
        }
        .animation(.easeOut(duration: 0.2), value: model.canShow)
        .animation(.easeOut(duration: 0.2), value: model.phase == .done)
    }
}

/// The puzzle's controls on a screen pushed over the dock (a theme, the daily): the one glass bar at the bottom.
struct PuzzleGlassBar: View {
    let model: PuzzleModel

    var body: some View {
        HStack(spacing: 0) {
            DockButton(symbol: "arrow.up.arrow.down", title: "Flip", label: "Flip the board", enabled: model.puzzle != nil) {
                Feel.shared.select()
                withAnimation(.easeInOut(duration: 0.25)) { model.flipped.toggle() }
            }
            .accessibilityIdentifier("puzzle-flip")
            DockButton(symbol: "arrow.counterclockwise", title: "Retry", label: "Try this puzzle again from the start", enabled: model.canRetry) {
                Task { await model.retry() }
            }
            .accessibilityIdentifier("puzzle-retry")
            if model.canShow {
                DockButton(symbol: "eye", title: "Show the move", label: "Show the move", enabled: true) {
                    Task { await model.showMove() }
                }
                .accessibilityIdentifier("puzzle-show")
                .transition(.opacity)
            }
            if !model.isDaily {
                DockButton(symbol: "arrow.right", title: "Next", label: model.phase == .done ? "Next puzzle" : "Skip to the next puzzle", enabled: model.canNext) {
                    Feel.shared.select()
                    Task { await model.next() }
                }
                .background(Capsule().fill(Z.wash.opacity(model.phase == .done ? 1.6 : 0)).padding(.vertical, 4))
                .accessibilityIdentifier("puzzle-next")
            }
        }
        .padding(.horizontal, 8)
        .glassDock()
        .animation(.easeOut(duration: 0.2), value: model.canShow)
        .animation(.easeOut(duration: 0.2), value: model.phase == .done)
    }
}

/// Debug builds with -puzzle-answers: the move the line expects, for UI tests. Nothing in a Release build.
struct PuzzleAnswerHook: View {
    let model: PuzzleModel

    var body: some View {
        #if DEBUG
        if Debug.args.contains("-puzzle-answers") {
            Color.clear.frame(width: 2, height: 2)
                .accessibilityElement()
                .accessibilityLabel(model.expected ?? "none")
                .accessibilityIdentifier("puzzle-expected")
        }
        #endif
    }
}

/// The top of a puzzle screen pushed over the dock: back at the left, a small label and a title in the middle.
struct PuzzleTop: View {
    let label: String
    let title: String
    @Binding var path: [Route]

    var body: some View {
        HStack(spacing: 12) {
            RoundIcon(symbol: "chevron.left", label: "Back") { if !path.isEmpty { path.removeLast() } }
                .accessibilityIdentifier("page-back")
            VStack(spacing: 2) {
                Text(label).font(Z.medium(10.5, relativeTo: .caption)).tracking(1.5).textCase(.uppercase).foregroundStyle(Z.dim)
                    .fixedSize(horizontal: false, vertical: true)
                // Wraps rather than cut short at large text sizes.
                Text(title).font(Z.medium(15)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("puzzle-top")
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }
}
