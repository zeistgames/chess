import SwiftUI

/// Where a game starts from, other than the usual start: a FEN or PGN pasted in (a PGN can be stepped to the move to
/// start from), or one of a few classic practice positions. Shown small on a board before it is chosen.
struct PositionSheet: View {
    @Binding var start: String
    @Binding var startName: String
    @Binding var side: Pick.Side
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var problem: String?
    @State private var fens: [String] = []
    @State private var san: [String] = []
    @State private var pgnStart = ""
    @State private var ply = 0
    @State private var chosen: String?
    @State private var chosenName = ""

    /// Practice positions worth having: the basic mates, and the endings every player learns.
    static let setups: [(name: String, fen: String)] = [
        ("King and queen against king", "8/8/8/4k3/8/8/8/3QK3 w - - 0 1"),
        ("King and rook against king", "8/8/8/4k3/8/8/8/R3K3 w - - 0 1"),
        ("Two bishops against king", "8/8/8/4k3/8/8/8/2B1KB2 w - - 0 1"),
        ("Bishop and knight against king", "8/8/8/4k3/8/8/8/1N2KB2 w - - 0 1"),
        ("King and pawn against king", "8/8/8/4k3/8/8/4P3/4K3 w - - 0 1"),
        ("The Lucena position", "1K1k4/1P6/8/8/8/8/r7/2R5 w - - 0 1"),
        ("The Philidor position, defending", "4k3/8/r7/4PK2/8/8/8/7R b - - 0 1"),
        ("Queen against a pawn on the seventh", "Q7/8/K7/8/8/8/2pk4/8 w - - 0 1"),
    ]

    private var preview: String? {
        if !fens.isEmpty { return fens.indices.contains(ply) ? fens[ply] : nil }
        return chosen
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("From a position").font(Z.title(28)).padding(.bottom, 6)
                Text("Paste a FEN or a PGN, or start from a classic position.")
                    .font(Z.text(14.5)).foregroundStyle(Z.soft).fixedSize(horizontal: false, vertical: true)

                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("FEN or PGN").font(Z.text(15)).foregroundStyle(Z.dim).padding(.horizontal, 15).padding(.vertical, 13)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(.system(size: 15, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .frame(height: 92)
                        .accessibilityLabel("FEN or PGN")
                        .accessibilityIdentifier("position-text")
                }
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Z.faint))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Z.hair, lineWidth: 1))
                .padding(.top, 18)
                HStack(spacing: 10) {
                    Button("Paste") { if let s = UIPasteboard.general.string { text = s; Task { await read() } } }
                        .buttonStyle(Pill(small: true)).accessibilityIdentifier("paste")
                    Button("Read it") { Task { await read() } }.buttonStyle(Pill(small: true)).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("read")
                    Spacer()
                }
                .padding(.top, 10)
                if let problem {
                    Text(problem).font(Z.text(14)).foregroundStyle(Z.soft).padding(.top, 10).accessibilityIdentifier("position-problem")
                }

                if let fen = preview {
                    HStack(alignment: .center, spacing: 16) {
                        BoardStill(fen: fen, flipped: fen.split(separator: " ").dropFirst().first == "b")
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Z.ink.opacity(0.18), lineWidth: 1))
                            .frame(width: 150, height: 150)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(chosenName.isEmpty ? "Your position" : chosenName).font(Z.medium(15)).fixedSize(horizontal: false, vertical: true)
                            Text(fen.split(separator: " ").dropFirst().first == "b" ? "Black to move." : "White to move.")
                                .font(Z.text(13.5)).foregroundStyle(Z.soft)
                            if !fens.isEmpty {
                                Text(ply == 0 ? "The start of the game." : "After \(GameModel.moveNumber(ply, start: pgnStart)) \(san[ply - 1]).")
                                    .font(Z.text(13.5)).foregroundStyle(Z.soft).accessibilityIdentifier("position-ply")
                                HStack(spacing: 8) {
                                    StepButton(symbol: "chevron.left", label: "Back a move", enabled: ply > 0) { ply -= 1 }
                                    StepButton(symbol: "chevron.right", label: "Forward a move", enabled: ply < fens.count - 1) { ply += 1 }
                                }
                            }
                        }
                    }
                    .padding(.top, 18)
                    .transition(.opacity)
                    Button("Start from here") { Task { await use(fen) } }.buttonStyle(Pill(solid: true, wide: true)).padding(.top, 18)
                        .accessibilityIdentifier("use-position")
                }

                Text("Practice").zLabel().padding(.top, 30).padding(.bottom, 4)
                VStack(spacing: 0) {
                    ForEach(Self.setups, id: \.fen) { s in
                        Button {
                            text = ""; problem = nil; fens = []; chosen = s.fen; chosenName = s.name; Feel.shared.select()
                        } label: {
                            HStack {
                                Text(s.name).font(Z.text(15.5)).foregroundStyle(chosen == s.fen ? Z.ink : Z.soft)
                                Spacer()
                                Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).opacity(chosen == s.fen ? 1 : 0)
                            }
                            .padding(.vertical, 12).contentShape(Rectangle())
                        }
                        .buttonStyle(Press())
                        .accessibilityAddTraits(chosen == s.fen ? .isSelected : [])
                        Rectangle().fill(Z.hair).frame(height: 1)
                    }
                }
                if !start.isEmpty {
                    Button("Back to the usual start") { start = ""; startName = ""; Feel.shared.select(); dismiss() }
                        .buttonStyle(Pill(wide: true)).padding(.top, 22).accessibilityIdentifier("usual-start")
                }
                Text("Games from a position don't change your adaptive level.")
                    .font(Z.text(13)).foregroundStyle(Z.dim).padding(.top, 18).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24).padding(.top, 30).padding(.bottom, 24)
            .animation(.easeOut(duration: 0.2), value: preview)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(Z.ink)
        .presentationBackground(Z.raised)
        .presentationDetents([.large])
        .presentationCornerRadius(30)
        .presentationDragIndicator(.visible)
        .onAppear { if !start.isEmpty { chosen = start; chosenName = startName } }
    }

    private func read() async {
        problem = nil
        guard let v = try? await Core.shared.call("parse", ["text": text]) as? [String: Any] else {
            problem = "That couldn't be read. Try again."; ReviewRequest.shared.record(.trouble); return
        }
        if let e = v["error"] as? String { problem = e; fens = []; chosen = nil; Feel.shared.refuse(); return }
        chosenName = ""
        if (v["kind"] as? String) == "pgn", let f = v["fens"] as? [String], let s = v["san"] as? [String], f.count > 1 {
            fens = f; san = s; pgnStart = v["start"] as? String ?? GameModel.standardStart
            ply = f.count - 1
            chosen = nil
        } else {
            fens = []
            chosen = (v["start"] as? String) ?? (v["fens"] as? [String])?.first
        }
        Feel.shared.select()
    }

    private func use(_ fen: String) async {
        // A position that is already over can't be played from.
        if let v = try? await Core.shared.call("parse", ["text": fen]) as? [String: Any], let e = v["error"] as? String {
            problem = e; Feel.shared.refuse(); return
        }
        start = fen
        startName = chosenName
        side = fen.split(separator: " ").dropFirst().first == "b" ? .black : .white
        Feel.shared.select()
        dismiss()
    }
}
