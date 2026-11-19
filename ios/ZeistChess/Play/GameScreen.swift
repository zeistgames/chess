import SwiftUI

/// A game against an engine, in the layout chess players know: the moves in a line at the top, the engine's row
/// above the board and yours below it (what each has taken, the clocks), back and forward at the bottom.
struct GameScreen: View {
    @State var model: GameModel
    @Binding var path: [Route]
    @State private var help = false
    @State private var resigning = false
    @State private var showEnd = false
    @State private var again = false
    @AppStorage(Look.edgeKey) private var edge = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var size
    @Environment(\.scenePhase) private var phase
    /// The card's place under the board in a game from Learn, kept whether or not a card shows, so the board never
    /// moves. It grows a little with the text size but never past 124 points, so the board always keeps its room;
    /// the card's words scroll inside it rather than being cut.
    @ScaledMetric(relativeTo: .body) private var scaledSlot: CGFloat = 112
    private var cardSlot: CGFloat { min(scaledSlot, 126) }

    private var gutter: CGFloat { size == .regular ? 40 : 14 }
    /// Learn as you play's cards: only for a game started from Learn.
    private var cards: GameCards? { model.record.learn == true ? GameCards.of(model.record.id) : nil }
    private var opponent: String { model.player == "w" ? "b" : "w" }

    var body: some View {
        VStack(spacing: 0) {
            bar
            MoveLine(san: model.record.san, startFEN: model.record.startFEN, shown: model.shownPly) { model.step(to: $0) }
                .padding(.top, 4)
            Spacer(minLength: 4)
            VStack(spacing: 0) {
                row(model.whiteAtBottom ? "b" : "w").padding(.bottom, 9)
                BoardView(model: model, square: edge && size != .regular)
                    .shadow(color: .black.opacity(edge ? 0 : 0.35), radius: 18, y: 12)
                    .padding(.horizontal, edge && size != .regular ? 0 : gutter)
                row(model.whiteAtBottom ? "w" : "b").padding(.top, 9)
            }
            .frame(maxWidth: 720)
            Text(model.status)
                .font(Z.text(14.5)).foregroundStyle(Z.soft)
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
                .frame(minHeight: 22).padding(.horizontal, 28).padding(.top, 10)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: model.status)
                .accessibilityIdentifier("status")
                .opacity(showEnd || model.statusIsPlain ? 0 : 1)
            if let cards {
                // Learn as you play: the card's place, under the status line, the same height with or without a card.
                ZStack(alignment: .top) {
                    if let c = cards.current, !showEnd {
                        PlayCardView(card: c, fen: fen(at: c.card.shows), flipped: model.player == "b", height: cardSlot - 6,
                                     open: { Feel.shared.select(); path.append(c.route) }, close: { cards.dismiss() })
                            .padding(.horizontal, size == .regular ? gutter : 16)
                            .frame(maxWidth: 560)
                            .transition(.opacity)
                    }
                }
                .frame(height: cardSlot, alignment: .top)
                .padding(.top, 6)
                .animation(.easeOut(duration: 0.2), value: cards.current?.key)
            }
            Spacer(minLength: 4)
            actions
                .padding(.horizontal, 16).padding(.bottom, 12)
                .frame(maxWidth: 720)
                .opacity(showEnd ? 0 : 1)
                .accessibilityHidden(showEnd)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // In a game from Learn the card takes a place under the board, so the words around it stop growing at the
        // first accessibility size and the board always keeps its room. Other games are as they were.
        .dynamicTypeSize(cards == nil ? DynamicTypeSize.xSmall ... DynamicTypeSize.accessibility5 : DynamicTypeSize.xSmall ... DynamicTypeSize.accessibility1)
        .background(Z.ground.ignoresSafeArea())
        .foregroundStyle(Z.ink)
        .overlay {
            if showEnd, model.over {
                EndCard(model: model, found: cards?.found ?? [], open: { path.append($0) }, again: { Task { await playAgain() } }, swap: { Task { await playAgain(swap: true) } }, board: { withAnimation(.easeOut(duration: 0.2)) { showEnd = false } },
                        review: { let id = model.record.id; dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { path.append(.replay(id)) } },
                        leave: { dismiss() })
                    .transition(.opacity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $help) { HelpSheet(model: model) }
        .task { await model.resume() }
        // After every move (and at the end), what has come up in a game from Learn.
        .task(id: "\(model.record.id)-\(model.record.moves.count)-\(model.over)") {
            guard let cards else { return }
            await cards.update(moves: model.record.moves, player: model.player, fen: model.record.startFEN, learn: true, over: model.over)
        }
        .onChange(of: model.over) { _, over in
            guard over else { showEnd = false; return }
            // GameModel.endCardIn is this pause and fade together.
            Task { try? await Task.sleep(for: .seconds(0.9)); withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.4)) { showEnd = model.over } }
        }
        .onChange(of: phase) { _, p in
            if p == .background { model.pauseClock() }
            if p == .active, !model.over, !model.thinking { Task { await model.resume() } }
        }
        .onAppear { Feel.shared.prepare() }
        .onDisappear { model.leave() }
    }

    /// The side at the top or the bottom of the board: name, level, captures and clock.
    private func row(_ color: String) -> some View {
        let you = color == model.player
        let toMove = !model.over && model.snap.turn == color
        return PlayerRow(name: you ? "You" : model.engineName, detail: you ? nil : model.levelLine, color: color, board: model.shownBoard,
                         start: model.startBoard, toMove: toMove, mine: you, clock: model.timed ? AnyView(clock(color)) : nil,
                         face: you ? nil : AnyView(EngineFace(id: model.engine.id, name: model.engineName, thinking: model.thinking && !model.over)))
            .padding(.horizontal, edge && size != .regular ? 16 : gutter + 2)
    }

    /// The position after n moves, for a card's small board.
    private func fen(at n: Int) -> String {
        let p = model.positions
        if p.indices.contains(n), !p[n].isEmpty { return p[n] }
        return model.snap.fen
    }

    private func clock(_ color: String) -> some View {
        let running = model.clock?.running == color && model.clock?.paused == false && !model.over
        return TimelineView(.periodic(from: .now, by: running ? 0.1 : 3600)) { t in
            let left = model.timeLeft(color) ?? 0
            ClockFace(seconds: left, running: running, low: left <= (model.record.timeControl?.lowTime ?? 0), mine: color == model.player)
        }
        .accessibilityIdentifier(color == model.player ? "clock-you" : "clock-engine")
    }

    /// Bottom: one bar in the order chess players know (Menu, then Undo and Hint in games without a clock, Back,
    /// Forward), in Liquid Glass like the dock of the main Zeist app. After the end, or in trouble, what comes next
    /// sits just above it.
    private var actions: some View {
        VStack(spacing: 10) {
            if model.over {
                HStack(spacing: 8) {
                    Button(again ? "Starting" : "Play again") { Task { await playAgain() } }.buttonStyle(Pill(solid: true)).disabled(again)
                    Button("Home") { dismiss() }.buttonStyle(Pill())
                }
            } else if model.trouble != nil {
                Button("Try again") { model.retry() }.buttonStyle(Pill(solid: true))
            }
            HStack(spacing: 0) {
                menu
                if !model.timed, !model.over {
                    DockButton(symbol: "arrow.uturn.backward", title: "Undo", label: "Undo", enabled: model.canUndo) { model.undo() }
                        .accessibilityIdentifier("undo")
                    DockButton(symbol: "lightbulb", title: model.hinting ? "Thinking" : "Hint", label: "Hint", enabled: model.canHint) { model.askHint() }
                        .accessibilityIdentifier("hint")
                }
                DockButton(symbol: "chevron.left", title: "Back", label: "Back a move", enabled: model.shownPly > 0) { model.stepBack() }
                    .accessibilityIdentifier("step-back")
                DockButton(symbol: "chevron.right", title: "Forward", label: "Forward a move", enabled: model.viewPly != nil) { model.stepForward() }
                    .accessibilityIdentifier("step-forward")
            }
            .padding(.horizontal, 8)
            .glassDock()
        }
        .confirmationDialog("Resign this game?", isPresented: $resigning, titleVisibility: .visible) {
            Button("Resign", role: .destructive) { model.resign() }
            Button("Keep playing", role: .cancel) {}
        } message: { Text("\(model.engineName) wins.") }
    }

    /// Everything rarer, in a menu that opens from its own place in the bar: a draw, resigning, turning the board,
    /// how the engine plays, copying and sharing the game.
    private var menu: some View {
        Menu {
            if !model.over {
                Button { model.offerDraw() } label: { Label("Offer a draw", systemImage: "equal") }
                    .disabled(!model.canOfferDraw)
                    .accessibilityIdentifier("offer-draw")
                Button(role: .destructive) { resigning = true } label: { Label("Resign", systemImage: "flag") }
                    .accessibilityIdentifier("menu-resign")
            }
            Section {
                Button {
                    Feel.shared.select()
                    withAnimation(.easeInOut(duration: 0.25)) { model.flipped.toggle() }
                } label: { Label("Flip the board", systemImage: "arrow.up.arrow.down") }
                    .accessibilityIdentifier("flip")
                Button { help = true } label: { Label("How it plays", systemImage: "questionmark.circle") }
            }
            Section {
                ShareLink(item: model.pgn, subject: Text("A game of chess"), preview: SharePreview("Zeist Chess game")) {
                    Label("Share the game", systemImage: "square.and.arrow.up")
                }
                Button { UIPasteboard.general.string = model.pgn; Feel.shared.select() } label: { Label("Copy PGN", systemImage: "doc.on.doc") }
                Button { UIPasteboard.general.string = model.shownFEN; Feel.shared.select() } label: { Label("Copy FEN", systemImage: "square.on.square") }
            }
        } label: {
            DockLabel(symbol: "line.3.horizontal", title: "Menu")
        }
        .foregroundStyle(Z.ink)
        .accessibilityLabel("More")
        .accessibilityIdentifier("game-menu")
    }

    /// The same opponent, side, clock and kind of difficulty, at the level that comes next. With swap, the other side.
    private func playAgain(swap: Bool = false) async {
        guard !again else { return }
        again = true
        defer { again = false }
        let r = model.record
        let level = r.adaptive ? await GameModel.startingLevel(r.engineID) : r.level
        let side = UserDefaults.standard.string(forKey: Pick.sideKey).flatMap(Pick.Side.init(rawValue:)) ?? .either
        var player = side == .either ? (Bool.random() ? "w" : "b") : r.player
        if swap { player = r.player == "w" ? "b" : "w" }
        if let m = try? await GameModel.begin(engine: model.engine, player: player, level: level, adaptive: r.adaptive, rating: r.rating, time: r.timeControl,
                                              start: r.startFEN, learn: r.learn == true) {
            Session.shared.game = m
            model = m
            showEnd = false
            Feel.shared.select()
            await m.resume()
        }
    }

    private var bar: some View {
        HStack(spacing: 10) {
            RoundIcon(symbol: "chevron.left", label: "Home") { dismiss() }
            Spacer(minLength: 4)
            // The clock's kind, and the opening's name while the game is young, quietly in the middle.
            VStack(spacing: 3) {
                if model.record.learn == true {
                    Text("Learn as you play").zLabel().lineLimit(1).accessibilityIdentifier("learn-game")
                }
                if let tc = model.record.timeControl {
                    Text("\(tc.kind.name)  \(tc.name)").zLabel().lineLimit(1)
                        .accessibilityLabel("\(tc.kind.name), \(tc.name)")
                }
                if let o = model.openingLine {
                    Text(o).font(Z.text(12.5)).foregroundStyle(Z.dim).lineLimit(1).minimumScaleFactor(0.85).truncationMode(.tail)
                        .transition(.opacity)
                        .accessibilityLabel("Opening: \(o)")
                        .accessibilityIdentifier("opening")
                }
            }
            .animation(.easeOut(duration: 0.25), value: model.openingLine)
            Spacer(minLength: 4)
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }
}

/// The end of a game: plain words, the board dimmed behind, what comes next. Kind whatever the result.
struct EndCard: View {
    let model: GameModel
    /// In a game from Learn: what came up, each with its lesson.
    var found: [ShownCard] = []
    var open: (Route) -> Void = { _ in }
    let again: () -> Void
    let swap: () -> Void
    let board: () -> Void
    let review: () -> Void
    let leave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer()
            Text(model.ending.title).font(Z.title(44, relativeTo: .largeTitle)).foregroundStyle(Z.ink).lineLimit(2).minimumScaleFactor(0.6)
            Text(detail).font(Z.text(16.5)).foregroundStyle(Z.soft).padding(.bottom, found.isEmpty ? 20 : 8).fixedSize(horizontal: false, vertical: true)
            if !found.isEmpty { cameUp.padding(.bottom, 16) }
            HStack(spacing: 10) {
                Button("Play again", action: again).buttonStyle(Pill(solid: true, wide: true)).accessibilityIdentifier("play-again")
                Button(model.player == "w" ? "Play Black" : "Play White", action: swap).buttonStyle(Pill(wide: true))
                    .accessibilityLabel("Rematch, playing \(model.player == "w" ? "Black" : "White")")
                    .accessibilityIdentifier("rematch")
            }
            HStack(spacing: 10) {
                Button("Home", action: leave).buttonStyle(Pill(wide: true)).accessibilityIdentifier("end-home")
                ShareLink(item: model.pgn, preview: SharePreview("Zeist Chess game")) { Text("Share") }
                    .buttonStyle(Pill(wide: true)).accessibilityIdentifier("share")
            }
            HStack(spacing: 22) {
                Button(action: board) { Text("See the board").underline() }
                Button(action: review) { Text("Go through the game").underline() }.accessibilityIdentifier("review")
            }
            .font(Z.text(14)).foregroundStyle(Z.soft).buttonStyle(.plain)
            .frame(maxWidth: .infinity).padding(.top, 10)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(stops: [.init(color: Z.ground.opacity(0.55), location: 0), .init(color: Z.ground.opacity(0.8), location: 0.45), .init(color: Z.ground.opacity(0.97), location: 0.75)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// What came up in a game from Learn, each once, with the way to its lesson.
    private var cameUp: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("In this game").zLabel().padding(.bottom, 4).accessibilityAddTraits(.isHeader)
            ForEach(found.prefix(6)) { c in
                Button { Feel.shared.select(); open(c.route) } label: {
                    HStack(spacing: 10) {
                        Text(c.title).font(Z.medium(15.5)).foregroundStyle(Z.ink).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Text(c.isOpening ? "The opening" : c.link).font(Z.text(13.5)).foregroundStyle(Z.lesson).lineLimit(1)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium)).foregroundStyle(Z.lesson)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(Press())
                .accessibilityLabel("\(c.title). Opens \(c.isOpening ? "the opening" : c.link).")
                .accessibilityIdentifier("came-up-\(c.key)")
            }
        }
    }

    /// How it ended, how long it lasted, and where the next game starts. No verdicts.
    private var detail: String {
        let r = model.record
        let moves = (r.moves.count + 1) / 2
        var parts = [model.ending.detail.isEmpty ? nil : model.ending.detail, "\(moves) \(moves == 1 ? "move" : "moves")."]
        if r.adaptive, let n = model.nextLevel {
            switch r.outcome {
            case "loss" where n < r.level: parts.append("Your next game is at level \(n), easier.")
            case "win" where n > r.level: parts.append("Your next game is at level \(n), harder.")
            default: parts.append("Your next game is at level \(n).")
            }
        }
        parts.append("The game is kept in Recent.")
        return parts.compactMap { $0 }.joined(separator: " ")
    }
}

/// What ? shows: how a game here works, and who made the engine.
struct HelpSheet: View {
    let model: GameModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(model.engineName).font(Z.title(36)).lineLimit(2).minimumScaleFactor(0.6)
                if let line = model.engine.manifest.line { Text(line).font(Z.text(16)).foregroundStyle(Z.soft) }
                Text("How it plays").zLabel().padding(.top, 6)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rules.enumerated()), id: \.offset) { i, rule in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(i + 1)").font(Z.text(12)).foregroundStyle(Z.dim).frame(width: 14, alignment: .leading)
                            Text(rule).font(Z.text(15.5)).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 10)
                        Rectangle().fill(Z.hair).frame(height: 1)
                    }
                }
                .overlay(alignment: .top) { Rectangle().fill(Z.hair).frame(height: 1) }
                Text([model.engine.manifest.author, model.engine.manifest.license].compactMap { $0 }.joined(separator: ". "))
                    .font(Z.text(13)).foregroundStyle(Z.dim)
                Button("Back to the game") { dismiss() }.buttonStyle(Pill(wide: true)).padding(.top, 8)
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(Z.ink)
        .presentationBackground(Z.raised)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(30)
    }

    private var rules: [String] {
        [
            "Tap a piece, then a square. Or drag the piece there.",
            "Checkmate wins. Stalemate, the same position three times, fifty moves without a capture or pawn move, and too little material to checkmate are draws.",
            model.record.adaptive
                ? "This game is at level \(model.record.level) of 10. Adaptive play goes up a level after you win and down a level after you lose."
                : "This game is at level \(model.record.level) of 10, chosen by you.",
            model.timed
                ? "Timed games have no Undo. While \(model.engineName) thinks you can set your next move; it is played the moment your turn comes, if it is legal then. Tap anywhere to cancel it."
                : "Undo takes back your last move. Hint shows a strong move as an arrow; a win with hints does not raise your level. Games here are not rated.",
            "Tap a move in the line at the top, or use the arrows, to look back. Tap the board to return.",
            "The menu at the bottom offers a draw. \(model.engineName) takes it when its own evaluation is about level and the game is past the opening.",
            "Every game is kept on this iPhone, move by move.",
        ]
    }
}
