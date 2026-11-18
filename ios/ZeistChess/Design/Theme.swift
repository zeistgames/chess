import SwiftUI

/// Zeist's room: graphite ground, bone text, Prata for titles and Jost for the rest.
/// Values from Zeist's design tokens (room.dark, piece, mark.strategy, board_default).
enum Z {
    static let ground = Color(red: 0x12 / 255, green: 0x11 / 255, blue: 0x0E / 255)
    static let raised = Color(red: 0x1C / 255, green: 0x1A / 255, blue: 0x16 / 255)
    static let ink = Color(red: 0xF4 / 255, green: 0xF1 / 255, blue: 0xEA / 255)
    static let soft = ink.opacity(0.66)
    static let dim = ink.opacity(0.42)
    static let hair = ink.opacity(0.12)
    static let wash = ink.opacity(0.07)
    static let faint = ink.opacity(0.05)
    /// What just happened: the last move. Zeist's orange for strategy games.
    static let mark = Color(red: 1.0, green: 0x74 / 255, blue: 0x42 / 255)
    /// Zeist's mark for Puzzles and Classics (mark.puzzle in the tokens): a lesson's rings and arrows, and Continue in Learn.
    static let lesson = Color(red: 1.0, green: 0xBB / 255, blue: 0x2E / 255)
    /// Switches, as in Zeist's settings.
    static let amber = Color(red: 0xC8 / 255, green: 0x92 / 255, blue: 0x5A / 255)

    static let ivory = Color(red: 0xEE / 255, green: 0xE7 / 255, blue: 0xD6 / 255)
    static let ebony = Color(red: 0x1C / 255, green: 0x1B / 255, blue: 0x18 / 255)

    /// The board: slate at OKLCH lightness .56 (board_default), so ivory and ebony read equally on it.
    static let board = Color(red: 0.4078, green: 0.4627, blue: 0.5255)

    static func title(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom("Prata-Regular", size: size, relativeTo: style)
    }
    static func text(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Jost-Regular", size: size, relativeTo: style)
    }
    static func medium(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Jost-Medium", size: size, relativeTo: style)
    }
}

extension View {
    /// Small capitals, widely spaced.
    func zLabel() -> some View {
        font(Z.medium(11, relativeTo: .caption)).tracking(1.6).textCase(.uppercase).foregroundStyle(Z.soft)
    }

    func card(_ radius: CGFloat = 22) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Z.raised))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Z.hair, lineWidth: 1))
    }
}

/// A pill. Solid for the one main action on a screen, outlined for the rest.
struct Pill: ButtonStyle {
    var solid = false
    var wide = false
    var small = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Z.medium(small ? 14 : 16))
            .lineLimit(1)
            .foregroundStyle(solid ? Z.ground : Z.ink)
            .padding(.horizontal, small ? 16 : 22)
            .frame(minHeight: small ? 36 : 50)
            .frame(maxWidth: wide ? .infinity : nil)
            .background(Capsule().fill(solid ? Z.ink : Color.clear))
            .overlay(Capsule().strokeBorder(solid ? Color.clear : Z.hair, lineWidth: 1))
            .contentShape(Capsule())
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.38)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Dips when pressed, for cards.
struct Press: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

/// A round, quiet icon button for the top bar.
struct RoundIcon: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Z.soft)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Z.faint))
                .contentShape(Circle())
        }
        .buttonStyle(Press())
        .accessibilityLabel(label)
    }
}

/// A choice drawn as pills inside a soft track.
struct Choice<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var value: T
    var height: CGFloat = 40

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { option in
                Button {
                    if value != option.0 { value = option.0; Feel.shared.select() }
                } label: {
                    Text(option.1)
                        .font(Z.medium(14))
                        .foregroundStyle(value == option.0 ? Z.ink : Z.soft)
                        .frame(maxWidth: .infinity, minHeight: height)
                        .background(Capsule().fill(value == option.0 ? Z.wash.opacity(1.6) : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(value == option.0 ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Z.faint))
        .animation(.spring(duration: 0.28), value: value)
    }
}

/// The Zeist mark with a pawn on its inner point, as on this app's icon.
struct ChessMark: View {
    var body: some View {
        Canvas { ctx, size in
            let k = size.width / 76, o = CGPoint(x: -12 * k, y: -12 * k)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * k, y: o.y + y * k) }
            var lines = Path()
            for y in [12.0, 44, 76] { lines.move(to: p(88, y)); lines.addLine(to: p(12, y)) }
            for x in [88.0, 56, 24] { lines.move(to: p(x, 12)); lines.addLine(to: p(x, 88)) }
            let pawn = ChessMark.pawn(center: p(56, 44.4), scale: k * 1.12)
            var masked = ctx
            masked.clipToLayer { layer in
                layer.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                layer.blendMode = .clear
                layer.stroke(pawn, with: .color(.white), style: StrokeStyle(lineWidth: 10 * k, lineJoin: .round))
                layer.fill(pawn, with: .color(.white))
            }
            masked.stroke(lines, with: .foreground, style: StrokeStyle(lineWidth: 3 * k * 1.5, lineCap: .round))
            ctx.fill(pawn, with: .foreground)
        }
        .accessibilityHidden(true)
    }

    /// The pawn of the icon, around its center.
    static func pawn(center c: CGPoint, scale s: CGFloat) -> Path {
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: c.x + x * s, y: c.y + y * s) }
        p.addEllipse(in: CGRect(x: c.x - 6.3 * s, y: c.y + (-10.6 - 6.3) * s, width: 12.6 * s, height: 12.6 * s))
        p.addRoundedRect(in: CGRect(x: c.x - 8.2 * s, y: c.y - 4.6 * s, width: 16.4 * s, height: 3.6 * s), cornerSize: CGSize(width: 1.8 * s, height: 1.8 * s))
        p.move(to: pt(-4.9, -2))
        p.addCurve(to: pt(-11.6, 12.4), control1: pt(-4.9, 5.2), control2: pt(-9.6, 8.6))
        p.addLine(to: pt(11.6, 12.4))
        p.addCurve(to: pt(4.9, -2), control1: pt(9.6, 8.6), control2: pt(4.9, 5.2))
        p.closeSubpath()
        p.addRoundedRect(in: CGRect(x: c.x - 13.6 * s, y: c.y + 11.4 * s, width: 27.2 * s, height: 4.8 * s), cornerSize: CGSize(width: 2.4 * s, height: 2.4 * s))
        return p
    }
}

/// An engine's face: a small line drawing made for Zeist Chess from the engine's name or emblem (core/faces), in
/// bone on a graphite disc. The Zeist engine wears the Zeist Chess mark. An engine with no drawing shows its
/// first letter. While the engine thinks, the drawing breathes.
struct EngineFace: View {
    let id: String
    var name = ""
    var size: CGFloat = 34
    var thinking = false
    @State private var breath = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(Z.raised)
            Group {
                if id == "zeist" {
                    ChessMark().frame(width: size * 0.5, height: size * 0.5)
                } else if UIImage(named: "Faces/\(id)") != nil {
                    Image("Faces/\(id)").resizable().scaledToFit().frame(width: size * 0.6, height: size * 0.6)
                } else {
                    Text(String(name.prefix(1)).uppercased()).font(Z.title(size * 0.44))
                }
            }
            .foregroundStyle(Z.ink)
            .scaleEffect(thinking && breath ? 1.1 : 1)
            .opacity(thinking && !breath ? 0.8 : 1)
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(Z.hair, lineWidth: 1))
        .onChange(of: thinking, initial: true) { _, on in
            guard !reduceMotion else { return }
            if on { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { breath = true } }
            else { withAnimation(.easeOut(duration: 0.2)) { breath = false } }
        }
        .accessibilityHidden(true)
    }
}
