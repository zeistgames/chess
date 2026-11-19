import SwiftUI

/// Learn as you play, on Learn's front page: an ordinary unrated game against the engine chosen on Play, at the
/// player's level, with no clock; the side as Play would choose it. A game from Learn in progress is picked up again
/// here. A game from Play in progress is ended only after asking.
struct LearnPlayEntry: View {
    @Binding var path: [Route]
    @State private var log = GameLog.shared
    @State private var level = 2
    @State private var starting = false
    @State private var confirming = false
    @State private var problem: String?
    @AppStorage(Pick.engineKey) private var engineID = Shelf.bundledID
    @AppStorage(Pick.manualKey) private var manual = false
    @AppStorage(Pick.levelKey) private var manualLevel = 3
    @AppStorage(Pick.sideKey) private var side: Pick.Side = .either

    private var engine: Engine? {
        Shelf.shared.engine(engineID).flatMap { $0.installed ? $0 : nil } ?? Shelf.shared.engine(Shelf.bundledID)
    }
    /// A game from Learn still going, on an engine that is here.
    private var inProgress: GameRecord? {
        log.current.flatMap { $0.learn == true && Shelf.shared.engine($0.engineID)?.installed == true ? $0 : nil }
    }

    var body: some View {
        let name = inProgress?.engineName ?? engine?.name ?? "the engine"
        let line = inProgress.map { "Your game against \($0.engineName), move \($0.moves.count / 2 + 1)." }
            ?? "A game against \(name), level \(manual ? manualLevel : level). When an opening or a pattern comes up, a card names it."
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Learn as you play").font(Z.title(21, relativeTo: .title3)).fixedSize(horizontal: false, vertical: true)
                    Text(line).font(Z.text(13.5)).foregroundStyle(Z.soft).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(starting ? "Starting" : inProgress != nil ? "Continue" : "Play") { tapped() }
                    .buttonStyle(Pill(solid: true, small: true))
                    .disabled(starting || (engine == nil && inProgress == nil))
                    .accessibilityIdentifier("learn-play")
            }
            if let problem { Text(problem).font(Z.text(13.5)).foregroundStyle(Z.soft) }
        }
        .padding(16)
        .card(26)
        .accessibilityElement(children: .contain)
        .task(id: engineID) { if let e = engine { level = await GameModel.startingLevel(e.id) } }
        .confirmationDialog("You have a game in progress.", isPresented: $confirming, titleVisibility: .visible) {
            Button("Start the game", role: .destructive) { Task { await start() } }
            Button("Keep my game", role: .cancel) {}
        } message: { Text("Starting a game from Learn ends it.") }
    }

    private func tapped() {
        Feel.shared.select()
        if let g = inProgress, let e = Shelf.shared.engine(g.engineID) {
            Session.shared.game = GameModel(record: g, engine: e)
            path.append(.game)
            return
        }
        if log.current != nil { confirming = true } else { Task { await start() } }
    }

    private func start() async {
        guard !starting, let e = engine else { return }
        starting = true
        problem = nil
        defer { starting = false }
        let lvl = manual ? manualLevel : await GameModel.startingLevel(e.id)
        let player = side == .white ? "w" : side == .black ? "b" : (Bool.random() ? "w" : "b")
        do {
            let m = try await GameModel.begin(engine: e, player: player, level: lvl, adaptive: !manual, rating: nil, time: nil, learn: true)
            Session.shared.game = m
            path.append(.game)
        } catch {
            problem = "The game couldn't start. Try again."
            ReviewRequest.shared.record(.trouble)
        }
    }
}
