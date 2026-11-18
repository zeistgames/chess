import SwiftUI

/// The moves in one line that scrolls sideways: "1. e4 e5 2. ♘f3 ♞c6". Pieces are small figures in the chosen set;
/// pawn moves are plain. The move shown on the board is quietly marked, and the newest is kept in view.
struct MoveLine: View {
    let san: [String]
    let startFEN: String
    /// Moves played before the position shown (0 is the start).
    let shown: Int
    let step: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var blackFirst: Bool { startFEN.split(separator: " ").dropFirst().first == "b" }
    private var startNo: Int { Int(startFEN.split(separator: " ").last ?? "1") ?? 1 }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    if san.isEmpty {
                        Text("No moves yet").font(Z.text(14)).foregroundStyle(Z.dim).padding(.horizontal, 6)
                    }
                    ForEach(Array(san.enumerated()), id: \.offset) { i, move in
                        let ply = i + (blackFirst ? 1 : 0)
                        if ply % 2 == 0 || i == 0 {
                            Text("\(startNo + ply / 2)\(ply % 2 == 0 ? "." : "...")")
                                .font(Z.text(13.5)).foregroundStyle(Z.dim).monospacedDigit()
                                .padding(.leading, i == 0 ? 0 : 8).padding(.trailing, 1)
                                .accessibilityHidden(true)
                        }
                        Button { step(i + 1) } label: { MoveText(san: move, on: shown == i + 1) }
                            .buttonStyle(.plain)
                            .id(i + 1)
                            .accessibilityLabel("\(startNo + ply / 2), \(ply % 2 == 0 ? "White" : "Black"). \(Spoken.san(move))")
                            .accessibilityAddTraits(shown == i + 1 ? .isSelected : [])
                            .accessibilityIdentifier("ply-\(i + 1)")
                    }
                    Color.clear.frame(width: 1, height: 1).id(-1)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 34)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .onAppear { reader.scrollTo(shown == san.count ? -1 : max(1, shown), anchor: .center) }
            .onChange(of: shown) { _, n in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { reader.scrollTo(n == san.count ? -1 : max(1, n), anchor: n == san.count ? .trailing : .center) }
            }
            .onChange(of: san.count) { _, _ in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { reader.scrollTo(-1, anchor: .trailing) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Moves")
    }
}

/// One move: a piece figure and the rest of its notation, marked when it is the one on the board.
struct MoveText: View {
    let san: String
    var on = false

    var body: some View {
        let piece = san.first.flatMap { "KQRBN".contains($0) ? String($0) : nil }
        HStack(spacing: 1) {
            if let piece { Figure(kind: piece, size: 15).offset(y: -0.5) }
            Text(piece == nil ? san : String(san.dropFirst())).fixedSize()
        }
        .font(Z.medium(14.5))
        .foregroundStyle(on ? Z.ink : Z.soft)
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(Capsule().fill(on ? Z.wash.opacity(1.8) : .clear))
        .contentShape(Rectangle())
        .fixedSize()
    }
}

/// A small figure of a piece in the chosen set, drawn in the color of the text around it: a clean figurine.
struct Figure: View {
    let kind: String
    var size: CGFloat = 15
    @AppStorage(Look.piecesKey) private var chosen = PieceSets.file.default

    var body: some View {
        Image(PieceSets.image("b" + kind, set: chosen))
            .renderingMode(.template).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The pieces a side has taken, as small figures grouped by kind, with the lead when ahead ("+3").
struct Captures: View {
    let side: String
    let board: [String]
    /// The board the game started from, when not the usual start.
    var from: [String]? = nil
    var size: CGFloat = 16

    var body: some View {
        let taken = Material.captured(by: side, board, from: from)
        let lead = Material.lead(side, board)
        HStack(spacing: 4) {
            ForEach(taken, id: \.kind) { group in
                HStack(spacing: -size * 0.5) {
                    ForEach(0..<group.count, id: \.self) { _ in
                        // Each figure is cut out of the ground a little, so overlapping figures stay distinct.
                        Figure(kind: group.kind, size: size)
                            .background(Figure(kind: group.kind, size: size).foregroundStyle(Z.ground).offset(x: -1.2))
                    }
                }
            }
            if lead > 0 {
                Text("+\(lead)").font(Z.medium(12.5)).foregroundStyle(Z.dim).monospacedDigit().padding(.leading, 2)
            }
        }
        .frame(height: size)
        .foregroundStyle(Z.soft)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.words(taken, lead: lead))
    }

    static func words(_ taken: [(kind: String, count: Int)], lead: Int) -> String {
        let names = ["P": "pawn", "N": "knight", "B": "bishop", "R": "rook", "Q": "queen"]
        guard !taken.isEmpty else { return "Nothing taken" }
        let list = taken.map { "\($0.count) \(names[$0.kind]!)\($0.count == 1 ? "" : "s")" }.joined(separator: ", ")
        return "Taken: \(list)\(lead > 0 ? ". Ahead by \(lead)" : "")"
    }
}

/// A clock: the running one is bright, the other quiet; under its low-time mark it is drawn in Zeist's orange.
struct ClockFace: View {
    let seconds: Double
    let running: Bool
    let low: Bool
    let mine: Bool

    var body: some View {
        Text(ChessClock.say(seconds))
            .font(Z.medium(17, relativeTo: .headline)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.7)
            .foregroundStyle(low ? Z.mark : running ? Z.ground : Z.soft)
            .padding(.horizontal, 12)
            .frame(minWidth: 84, minHeight: 34)
            .background(Capsule().fill(low ? Z.mark.opacity(running ? 0.16 : 0.06) : running ? Z.ink : Z.faint))
            .overlay(Capsule().strokeBorder(low ? Z.mark.opacity(running ? 0.75 : 0.25) : running ? .clear : Z.hair, lineWidth: running && low ? 1.5 : 1))
            .animation(.easeOut(duration: 0.18), value: running)
            .animation(.easeOut(duration: 0.3), value: low)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(mine ? "Your clock" : "Engine's clock")
            .accessibilityValue("\(ChessClock.spoken(seconds))\(running ? ", running" : "")")
    }
}

/// A player's row: a small disc in their color, the name, the level in small text, what they have taken, the clock.
struct PlayerRow: View {
    let name: String
    var detail: String? = nil
    let color: String
    let board: [String]
    var start: [String]? = nil
    let toMove: Bool
    var mine = false
    var clock: AnyView? = nil
    /// The engine's face, on its row.
    var face: AnyView? = nil

    private var title: some View {
        Text(name).font(Z.medium(15.5)).foregroundStyle(toMove ? Z.ink : Z.soft).lineLimit(1).truncationMode(.tail)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let face { face }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Disc(color: color).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                    // A long name keeps the line; the level gives way.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            title.fixedSize()
                            if let detail { Text(detail).font(Z.text(12.5)).foregroundStyle(Z.dim).lineLimit(1).fixedSize() }
                        }
                        title
                    }
                }
                Captures(side: color, board: board, from: start).padding(.leading, 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityValue(toMove ? "to move" : "")
            if let clock { clock }
        }
        .animation(.easeOut(duration: 0.2), value: toMove)
    }
}

/// A small disc in ivory or ebony, lit like the pieces.
struct Disc: View {
    let color: String
    var size: CGFloat = 11

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: color == "w" ? [Color(red: 0.99, green: 0.98, blue: 0.95), Z.ivory, Color(red: 0.83, green: 0.79, blue: 0.70)]
                                 : [Color(red: 0.29, green: 0.27, blue: 0.25), Z.ebony, .black],
                                 center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size))
            .overlay(Circle().strokeBorder(Z.ink.opacity(color == "b" ? 0.5 : 0), lineWidth: 1))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A round outlined control for stepping through moves.
struct StepButton: View {
    let symbol: String
    let label: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium))
                .frame(width: 50, height: 50)
                .overlay(Circle().strokeBorder(Z.hair, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(Press())
        .foregroundStyle(Z.ink)
        .opacity(enabled ? 1 : 0.32)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// One place in the game's bottom bar: a symbol with its word under it.
struct DockLabel: View {
    let symbol: String
    let title: String

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 19, weight: .medium)).frame(height: 24)
            Text(title).font(Z.text(11)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity).frame(height: 58)
        .contentShape(Rectangle())
    }
}

struct DockButton: View {
    let symbol: String
    let title: String
    let label: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) { DockLabel(symbol: symbol, title: title) }
            .buttonStyle(Press())
            .foregroundStyle(Z.ink)
            .opacity(enabled ? 1 : 0.32)
            .disabled(!enabled)
            .accessibilityLabel(label)
    }
}

extension View {
    /// The bottom bar's ground: Liquid Glass where the system has it (iOS 26), a thin material before that.
    @ViewBuilder func glassDock() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .capsule)
        } else {
            self.background(Capsule().fill(.ultraThinMaterial)).overlay(Capsule().strokeBorder(Z.hair, lineWidth: 1))
        }
    }
}
