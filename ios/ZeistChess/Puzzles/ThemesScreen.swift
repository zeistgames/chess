import SwiftUI

/// Themes: the groups of puzzles by idea, in themes.json's order, one per row, each with Zeist's hand-picked small
/// board for it (theme-boards.json), the pieces involved ringed. Pushed over the dock.
struct ThemesScreen: View {
    @Binding var path: [Route]
    @State private var solved: [String: Int] = [:]
    private let set = PuzzleSet.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageBar(path: $path)
                Text("Themes").font(Z.title(36, relativeTo: .largeTitle)).accessibilityAddTraits(.isHeader).padding(.top, 8)
                Text(set.themes.count == 1 ? "1 theme." : "\(set.themes.count) themes.").font(Z.text(14.5)).foregroundStyle(Z.soft).padding(.top, 6)
                if set.themes.isEmpty {
                    Text("No themes could be read.").font(Z.text(15)).foregroundStyle(Z.soft).padding(.top, 24)
                }
                VStack(spacing: 0) {
                    ForEach(Array(set.themes.enumerated()), id: \.element.id) { n, t in
                        if n > 0 { Rectangle().fill(Z.hair).frame(height: 1) }
                        ThemeRow(theme: t, board: set.themeBoards[t.id], solved: solved[t.id] ?? 0) { path.append(.theme(t.id)) }
                    }
                }
                .padding(.top, 14)
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
        .onAppear { count() }
    }

    /// Puzzles of each theme solved by this player.
    private func count() {
        let done = PuzzleProgress.load().done
        solved = Dictionary(uniqueKeysWithValues: set.themes.map { t in (t.id, t.ids.reduce(0) { $0 + (done[$1] == 1 ? 1 : 0) }) })
    }
}

struct ThemeRow: View {
    let theme: PuzzleTheme
    let board: ThemeBoard?
    let solved: Int
    let action: () -> Void

    var body: some View {
        let detail = [theme.count == 1 ? "1 puzzle" : "\(theme.count.formatted(.number.locale(Fmt.us))) puzzles", solved > 0 ? "\(solved) solved" : nil]
            .compactMap { $0 }.joined(separator: " · ")
        Button { Feel.shared.select(); action() } label: {
            HStack(spacing: 14) {
                // A theme with no board of its own gets a plain one.
                MiniBoard(fen: board?.fen ?? "8/8/8/8/8/8/8/8 w - - 0 1", last: board?.last, marks: board?.marks, size: 80, radius: 7)
                VStack(alignment: .leading, spacing: 3) {
                    Text(theme.name).font(Z.title(19, relativeTo: .headline)).fixedSize(horizontal: false, vertical: true)
                    Text(detail).font(Z.text(13)).foregroundStyle(Z.dim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Chevron()
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(Press())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(theme.name). \(detail).")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("theme-\(theme.id)")
    }
}

/// One theme's puzzles, pushed over the dock: the theme named quietly at the top, the puzzle, the glass bar.
/// Next stays inside the theme; the step and the record move exactly as anywhere else.
struct ThemePuzzleScreen: View {
    let id: String
    @Binding var path: [Route]
    @State private var model: PuzzleModel?
    private let set = PuzzleSet.shared

    var body: some View {
        VStack(spacing: 0) {
            PuzzleTop(label: "Theme", title: set.theme(id)?.name ?? "", path: $path)
            Spacer(minLength: 8)
            if let model {
                PuzzleBoardArea(model: model).frame(maxWidth: 720)
                Spacer(minLength: 8)
                PuzzleGlassBar(model: model).padding(.horizontal, 16).padding(.bottom, 12).frame(maxWidth: 720)
            } else {
                if set.theme(id) == nil { Text("This theme couldn't be read.").font(Z.text(15)).foregroundStyle(Z.soft) }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Z.ground.ignoresSafeArea())
        .foregroundStyle(Z.ink)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard model == nil, let t = set.theme(id) else { return }
            let m = PuzzleModel(source: .theme(t))
            model = m
            await m.start()
        }
    }
}
