import SwiftUI

/// Learn as you play's card under the board: the position small, what came up and one plain line of what happened,
/// and the way to its lesson in the lesson amber. Quiet: it never covers the board or the game's bar, and never
/// stops the game. Its height is fixed by the game screen; at large text sizes its words scroll inside it, never cut,
/// and the small board steps aside. Tapping it opens the lesson over the game; the cross puts it away.
struct PlayCardView: View {
    let card: ShownCard
    let fen: String
    let flipped: Bool
    let height: CGFloat
    let open: () -> Void
    let close: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !typeSize.isAccessibilitySize {
                MiniBoard(fen: fen, flipped: flipped, size: min(56, height - 24), radius: 6)
                    .onTapGesture(perform: open)
                    .accessibilityHidden(true)
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.title).font(Z.medium(15.5)).foregroundStyle(Z.ink)
                    Text(card.line).font(Z.text(13)).foregroundStyle(Z.soft)
                    Text("\(card.isOpening ? "Open the lesson" : card.link) \u{203A}").font(Z.medium(13)).foregroundStyle(Z.lesson)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: open)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(card.title). \(card.line)")
            .accessibilityHint("Opens \(card.isOpening ? "the opening's lesson" : card.link)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, open)
            .accessibilityIdentifier("play-card")
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Z.soft)
                    .frame(width: 26, height: 26).background(Circle().fill(Z.faint))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(Press())
            .padding(.top, -8).padding(.trailing, -10)
            .accessibilityLabel("Put the card away")
            .accessibilityIdentifier("play-card-close")
        }
        .padding(.leading, 12).padding(.trailing, 12).padding(.vertical, 10)
        // Large, but not so large that a card shows only a word at a time; longer words scroll.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .frame(height: height, alignment: .top)
        .card(18)
    }
}
