import SwiftUI

/// The moves that reach an opening, played on a board one at a time from the usual start, so the opening is seen
/// being reached rather than read. Steps back and forward, plays again; the notation sits small and quiet under it,
/// the move on the board in ink. With Reduce Motion it rests on the opening's position and nothing plays by itself.
struct OpeningReplay: View {
    let play: [String]
    let moves: String?
    let flipped: Bool
    @State private var board = ReplayBoard()
    @State private var auto: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A calm pace: about a second a move.
    static let beat = 1.0

    var body: some View {
        VStack(spacing: 0) {
            BoardView(model: board)
                .allowsHitTesting(false)
                .shadow(color: .black.opacity(0.3), radius: 14, y: 10)
                .padding(.horizontal, -4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(board.ply == 0 ? "The usual start" : "After \(board.ply) of \(play.count) moves")
                .accessibilityIdentifier("opening-board")
            HStack(spacing: 10) {
                StepButton(symbol: "chevron.left", label: "Back a move", enabled: board.ply > 0) { stop(); board.go(board.ply - 1) }
                    .accessibilityIdentifier("opening-back")
                StepButton(symbol: "chevron.right", label: "Forward a move", enabled: board.ply < board.count) { stop(); board.go(board.ply + 1) }
                    .accessibilityIdentifier("opening-forward")
                StepButton(symbol: "arrow.counterclockwise", label: "Play again", enabled: board.count > 0) { start() }
                    .accessibilityIdentifier("opening-again")
            }
            .padding(.top, 14)
            if let moves { notation(moves).padding(.top, 10).padding(.horizontal, 12) }
        }
        .frame(maxWidth: .infinity)
        .task {
            await board.load(play, flipped: flipped)
            if reduceMotion { board.go(board.count) } else { start() }
        }
        .onDisappear { stop() }
    }

    private func stop() {
        auto?.cancel()
        auto = nil
    }

    private func start() {
        stop()
        board.go(0)
        auto = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            while !Task.isCancelled, board.ply < board.count {
                board.go(board.ply + 1)
                try? await Task.sleep(for: .seconds(Self.beat))
            }
        }
    }

    /// "1.e4 e5 2.Nf3": each word is one move; the one on the board is in ink.
    private func notation(_ s: String) -> some View {
        let words = s.split(separator: " ").map(String.init).filter { !$0.allSatisfy { $0.isNumber || $0 == "." } }
        let marked = words.count == play.count ? board.ply - 1 : -1
        let text = words.enumerated().reduce(Text("")) { t, w in
            t + Text(w.offset == 0 ? w.element : " " + w.element)
                .foregroundColor(w.offset == marked ? Z.ink : Z.dim)
                .font(w.offset == marked ? Z.medium(13.5) : Z.text(13.5))
        }
        return text.multilineTextAlignment(.center)
            .animation(.easeOut(duration: 0.15), value: board.ply)
            .accessibilityLabel(s)
            .accessibilityIdentifier("opening-moves")
    }
}

/// The board under the replay: a position for each move of the line, from core's rules. Nothing can be moved.
@MainActor @Observable
final class ReplayBoard: BoardModel {
    private var snaps: [Snapshot] = [PuzzleModel.still(GameModel.standardStart)]
    private var line: [String] = []
    private(set) var ply = 0
    private(set) var ids: [Int?] = Array(repeating: nil, count: 64)
    private(set) var flipped = false
    private var nextID = 0
    var selected: Int?
    var promoting: (from: Int, to: Int)?

    var count: Int { snaps.count - 1 }
    var snap: Snapshot { snaps[min(ply, snaps.count - 1)] }

    init() { reset() }

    func load(_ play: [String], flipped: Bool) async {
        self.flipped = flipped
        line = play
        var out = [PuzzleModel.still(GameModel.standardStart)]
        for k in play.indices {
            guard let s = try? await PuzzleModel.coreRules(GameModel.standardStart, Array(play.prefix(k + 1))) else { break }
            out.append(s)
        }
        if let first = try? await PuzzleModel.coreRules(GameModel.standardStart, []) { out[0] = first }
        snaps = out
        ply = 0
        reset()
    }

    /// To move n of the line. One move forward glides the piece; anything else sets the board afresh.
    func go(_ n: Int) {
        let to = min(max(0, n), count)
        guard to != ply else { return }
        if to == ply + 1 { carry(line[ply]); ply = to } else { ply = to; reset() }
        // A promotion or anything unexpected: set the board afresh rather than show a piece without an identity.
        if ids.enumerated().contains(where: { snap.board[$0.offset].isEmpty != ($0.element == nil) }) { reset() }
    }

    private func reset() {
        ids = snap.board.map { $0.isEmpty ? nil : { nextID += 1; return nextID }() }
    }

    /// Carries each piece's identity along a move (castling's rook and en passant included), so it glides.
    private func carry(_ uci: String) {
        let c = Array(uci)
        guard c.count >= 4, let f = Square.index(String(c[0...1])), let t = Square.index(String(c[2...3])) else { return }
        let b = snap.board
        let piece = b[f]
        var ids = self.ids
        if piece.hasSuffix("P"), f % 8 != t % 8, b[t].isEmpty {
            let taken = t + (piece.hasPrefix("w") ? 8 : -8)
            if (0..<64).contains(taken) { ids[taken] = nil }
        }
        if piece.hasSuffix("K"), abs(f % 8 - t % 8) == 2 {
            let (rf, rt) = t % 8 == 6 ? (t + 1, t - 1) : (t - 2, t + 1)
            ids[rt] = ids[rf]; ids[rf] = nil
        }
        ids[t] = ids[f]; ids[f] = nil
        self.ids = ids
    }

    // MARK: BoardModel: a board to look at.

    var whiteAtBottom: Bool { !flipped }
    var viewPly: Int? { nil }
    var shownBoard: [String] { snap.board }
    var shownLast: String? { snap.last }
    var player: String { flipped ? "b" : "w" }
    var premove: (from: Int, to: Int)? { nil }
    var hint: (from: Int, to: Int)? { nil }
    var canPremove: Bool { false }
    func hints(from i: Int) -> [(to: Int, capture: Bool)] { [] }
    func canLift(_ i: Int) -> Bool { false }
    func tap(_ i: Int) {}
    func drop(from: Int, to: Int) {}
    func promote(_ piece: String) {}
}
