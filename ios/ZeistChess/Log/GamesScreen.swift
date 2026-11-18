import SwiftUI

/// Every finished game, newest first. Opening one steps through its moves.
struct GamesScreen: View {
    @Binding var path: [Route]
    @State private var log = GameLog.shared
    @State private var account = Account.shared
    /// Shown as a place in the dock, with no way back needed.
    var tab = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // As a place in the dock: the title and the profile button across the top, as on Play and Puzzles.
            if tab {
                HStack {
                    Text("Games").font(Z.title(32, relativeTo: .title)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    ProfileButton()
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
            }
            list
        }
        .background(Z.ground.ignoresSafeArea())
        .foregroundStyle(Z.ink)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !tab {
                    HStack {
                        RoundIcon(symbol: "chevron.left", label: "Back") { dismiss() }
                        Spacer()
                    }
                    .padding(.top, 6)
                    Text("Games").font(Z.title(34)).accessibilityAddTraits(.isHeader).padding(.top, 14)
                }
                if !account.signedIn {
                    SignInLine().padding(.top, 14)
                }
                let done = log.finished
                if done.isEmpty {
                    Text("Games you finish are kept here.").font(Z.text(15)).foregroundStyle(Z.dim).padding(.top, 28)
                } else {
                    Text("\(done.count) \(done.count == 1 ? "game" : "games")").zLabel().padding(.top, 28)
                    LazyVStack(spacing: 0) {
                        ForEach(done) { g in
                            Button { path.append(.replay(g.id)) } label: { GameRow(game: g) }.buttonStyle(Press())
                            Rectangle().fill(Z.hair).frame(height: 1)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Z.ground.ignoresSafeArea())
        .foregroundStyle(Z.ink)
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// One finished game, move by move: the same line of moves, rows and arrows as the game itself. No analysis.
struct ReplayScreen: View {
    let id: UUID
    @State private var fens: [String] = []
    @State private var ply = 0
    @AppStorage(Look.edgeKey) private var edge = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var size

    private var game: GameRecord? { GameLog.shared.games.first { $0.id == id } }
    private var square: Bool { edge && size != .regular }
    private var gutter: CGFloat { size == .regular ? 40 : 14 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                RoundIcon(symbol: "chevron.left", label: "Back") { dismiss() }
                Spacer()
                if let g = game {
                    ShareLink(item: GameLog.pgn(g), preview: SharePreview("Zeist Chess game")) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .medium)).foregroundStyle(Z.soft)
                            .frame(width: 40, height: 40).background(Circle().fill(Z.faint)).contentShape(Circle())
                    }
                    .buttonStyle(Press())
                    .accessibilityLabel("Share the game")
                    .accessibilityIdentifier("share-game")
                }
            }
            .padding(.horizontal, 16).padding(.top, 6)
            if let g = game {
                Text(summary(g)).font(Z.text(13.5)).foregroundStyle(Z.dim).multilineTextAlignment(.center)
                    .lineLimit(2).padding(.horizontal, 28).padding(.top, 2)
                MoveLine(san: g.san, startFEN: g.startFEN, shown: ply) { n in step(n - ply) }
                    .padding(.top, 8)
                Spacer(minLength: 2).frame(maxHeight: 44).layoutPriority(-1)
                let board = fens.indices.contains(ply) ? fens[ply] : g.startFEN
                let cells = Square.board(fromFEN: board)
                VStack(spacing: 0) {
                    row(g, g.player == "w" ? "b" : "w", cells).padding(.bottom, 9)
                    BoardStill(fen: board, flipped: g.player == "b",
                               last: ply > 0 && g.moves.indices.contains(ply - 1) ? g.moves[ply - 1] : nil, coordinates: true)
                        .clipShape(RoundedRectangle(cornerRadius: square ? 0 : 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Z.ink.opacity(square ? 0 : 0.22), lineWidth: 1))
                        .padding(.horizontal, square ? 0 : gutter)
                        .animation(.easeInOut(duration: 0.18), value: ply)
                    row(g, g.player, cells).padding(.top, 9)
                }
                .frame(maxWidth: 720)
            .layoutPriority(1)
                Text(moveLine(g)).font(Z.text(14.5)).foregroundStyle(Z.soft).frame(minHeight: 22).padding(.top, 10)
                    .accessibilityIdentifier("replay-move")
                Spacer(minLength: 8).layoutPriority(-1)
                HStack(spacing: 10) {
                    StepButton(symbol: "backward.end", label: "Start", enabled: ply > 0) { step(-ply) }
                    Spacer()
                    StepButton(symbol: "chevron.left", label: "Back a move", enabled: ply > 0) { step(-1) }
                    StepButton(symbol: "chevron.right", label: "Forward a move", enabled: ply < fens.count - 1) { step(1) }
                    Spacer()
                    StepButton(symbol: "forward.end", label: "End", enabled: ply < fens.count - 1) { step(fens.count - 1 - ply) }
                }
                .padding(.horizontal, 16).padding(.bottom, 12)
                .frame(maxWidth: 720)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Z.ground.ignoresSafeArea())
        .foregroundStyle(Z.ink)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard let g = game else { return }
            if let v = try? await Core.shared.call("replay", ["fen": g.startFEN, "moves": g.moves]) as? [String: Any], let f = v["fens"] as? [String] {
                fens = f
                ply = f.count - 1
            }
        }
    }

    private func row(_ g: GameRecord, _ color: String, _ cells: [String]) -> some View {
        let you = color == g.player
        let left = Self.clock(g, color, at: ply)
        let start = g.startFEN == GameModel.standardStart ? nil : Square.board(fromFEN: g.startFEN)
        return PlayerRow(name: you ? "You" : g.engineName, detail: you ? nil : g.difficulty, color: color, board: cells, start: start, toMove: false, mine: you,
                         clock: left.map { AnyView(ClockFace(seconds: Double($0) / 1000, running: false, low: false, mine: you)) })
            .padding(.horizontal, square ? 16 : gutter + 2)
    }

    /// A side's time left after `ply` moves, from the clock times kept with each move.
    static func clock(_ g: GameRecord, _ color: String, at ply: Int) -> Int? {
        guard let tc = g.timeControl else { return nil }
        let blackFirst = g.startFEN.split(separator: " ").dropFirst().first == "b"
        let clocks = g.clocks ?? []
        var i = min(ply, clocks.count) - 1
        while i >= 0 {
            let mover = (i % 2 == 0) != blackFirst ? "w" : "b"
            if mover == color { return clocks[i] }
            i -= 1
        }
        return tc.base * 1000
    }

    private func step(_ d: Int) {
        let n = max(0, min(fens.count - 1, ply + d))
        if n != ply { ply = n; Feel.shared.select() }
    }

    private func summary(_ g: GameRecord) -> String {
        let side = g.player == "w" ? "White" : "Black"
        let clock = g.timeControl.map { ", \($0.kind.name.lowercased()) \($0.name)" } ?? ""
        let opening = g.openingName.map { " \($0)." } ?? ""
        return "\(Fmt.long(g.startedAt)). You played \(side) at \(g.difficulty.prefix(1).lowercased() + g.difficulty.dropFirst())\(clock). \(GameRow.word(g)).\(opening)"
    }

    private func moveLine(_ g: GameRecord) -> String {
        guard ply > 0, g.san.indices.contains(ply - 1) else { return "The start" }
        return "\(GameModel.moveNumber(ply, start: g.startFEN)) \(g.san[ply - 1])"
    }
}
