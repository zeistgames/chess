import SwiftUI

/// On a rated game's end card: what the game did to the rating, or how far the first ten have come.
struct RatedResult: View {
    let model: GameModel

    var body: some View {
        let r = model.record
        VStack(alignment: .leading, spacing: 10) {
            if r.ratedSent == .counted {
                if let after = r.ratingAfter {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        if let before = r.ratingBefore {
                            Text(verbatim: String(before)).font(Z.text(17)).foregroundStyle(Z.dim).strikethrough(true, color: Z.dim)
                        }
                        Text(verbatim: String(after)).font(Z.title(34, relativeTo: .title)).monospacedDigit()
                        if let before = r.ratingBefore, after != before {
                            Text(verbatim: after > before ? "+\(after - before)" : "\u{2212}\(before - after)").font(Z.medium(16)).foregroundStyle(Z.soft)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: r.ratingBefore.map { "Your rating went from \(String($0)) to \(String(after))." } ?? "Your rating is \(String(after))."))
                    .accessibilityIdentifier("rated-change")
                } else if let n = r.ratedGames {
                    FirstTen(games: n)
                }
                if r.matched == true, let next = r.nextRatedLevel {
                    line("Your next rated game is against level \(next).")
                }
            } else {
                line(Self.waitingLine(r.ratedSent, sending: model.ratedSending))
            }
        }
    }

    static func waitingLine(_ sent: RatedFinishes.Sent?, sending: Bool) -> String {
        switch sent {
        case .pending: "Zeist is checking this result. It counts once it's checked."
        case .refused: "Zeist couldn't count this game."
        case .waiting: "The result goes to Zeist once you're back online."
        default: "Sending the result to Zeist."
        }
    }

    private func line(_ s: String) -> some View {
        Text(s).font(Z.text(15)).foregroundStyle(Z.soft).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("rated-line")
    }
}

/// The first ten rated games, as a bar and a line.
struct FirstTen: View {
    let games: Int

    var body: some View {
        let n = min(games, Rated.untilRanked)
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Z.faint)
                    Capsule().fill(Z.ink).frame(width: g.size.width * CGFloat(n) / CGFloat(Rated.untilRanked))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            Text("\(n) of \(Rated.untilRanked) rated games. Your rating shows after ten.")
                .font(Z.text(15)).foregroundStyle(Z.soft).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("rated-first-ten")
        }
    }
}

/// In the opponent sheet, under Difficulty: Rated, for the Zeist engine and an account. Signed out, the offer to
/// sign in; with another engine, why it can't be.
struct RatedRow: View {
    @Binding var on: Bool
    let zeist: Bool
    let changed: () -> Void
    @State private var account = Account.shared
    @State private var signingIn = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Rated").font(Z.medium(16))
                Text(!account.signedIn ? "Sign in to Zeist to play rated games and keep a rating."
                     : zeist ? "Counts toward your rating, with no hints or undo." : "Rated games are against the Zeist engine.")
                    .font(Z.text(13.5)).foregroundStyle(Z.soft).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if account.signedIn {
                Toggle("Rated", isOn: Binding(get: { on && zeist }, set: { on = $0; Feel.shared.select(); changed() }))
                    .labelsHidden().tint(Z.amber).disabled(!zeist)
                    .accessibilityIdentifier("rated-switch")
            } else {
                Button("Sign in") { Feel.shared.select(); signingIn = true }
                    .buttonStyle(Pill(small: true))
                    .accessibilityIdentifier("rated-sign-in")
            }
        }
        .padding(.vertical, 12)
        .opacity(account.signedIn && !zeist ? 0.6 : 1)
        .overlay(alignment: .top) { Rectangle().fill(Z.hair).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Z.hair).frame(height: 1) }
        .sheet(isPresented: $signingIn) { SignInSheet() }
    }
}

/// Your rating: the number, how it has moved, and the record. Opened from the account in Settings.
struct RatingScreen: View {
    @State private var book = RatingBook.shared
    @State private var log = GameLog.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let s = book.current
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Your rating").font(Z.title(30, relativeTo: .title)).accessibilityAddTraits(.isHeader)
                if let s, let r = s.rating {
                    Text(verbatim: String(r)).font(Z.title(64, relativeTo: .largeTitle)).monospacedDigit().padding(.top, 10)
                        .accessibilityIdentifier("rating-number")
                } else {
                    FirstTen(games: s?.games ?? 0).padding(.top, 18)
                }
                Text("From rated games against the Zeist engine, here and in Zeist. It's close to an online rating on Lichess.")
                    .font(Z.text(14.5)).foregroundStyle(Z.soft).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                if s?.ranked == true, book.readings.count >= 2 {
                    RatingChart(points: book.readings.suffix(RatingBook.chartLength).map(\.rating)).padding(.top, 22)
                }
                HStack(alignment: .top, spacing: 0) {
                    if s?.ranked == true, let h = book.highest { stat(String(h), "Highest") }
                    stat(String(s?.games ?? 0), "Rated games")
                    if let b = book.bestBeaten(in: log.games) { stat("Level \(b)", "Best beaten") }
                }
                .padding(.top, 22)
                VStack(spacing: 0) {
                    if s?.ranked == true, let rec = s?.record {
                        row("Won", String(rec.won)); row("Drawn", String(rec.drawn)); row("Lost", String(rec.lost))
                    }
                    if let name = s?.rank_name, s?.ranked == true { row("In Zeist", name, last: true) }
                }
                .padding(.top, 14)
                if s == nil {
                    Text("Your rating shows here once Zeist has answered. Check your connection.")
                        .font(Z.text(14)).foregroundStyle(Z.dim).padding(.top, 14).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24).padding(.top, 30).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(Z.ink)
        .presentationBackground(Z.raised)
        .presentationDetents([.large])
        .presentationCornerRadius(30)
        .presentationDragIndicator(.visible)
        .task { await RatedFinishes.flush(); await book.refresh() }
    }

    private func stat(_ value: String, _ name: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Z.medium(19)).monospacedDigit()
            Text(name).font(Z.text(13)).foregroundStyle(Z.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func row(_ name: String, _ value: String, last: Bool = false) -> some View {
        HStack {
            Text(name).font(Z.text(15.5)).foregroundStyle(Z.soft)
            Spacer()
            Text(value).font(Z.medium(15.5)).monospacedDigit()
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Z.hair).frame(height: 1) } }
        .accessibilityElement(children: .combine)
    }
}

/// The ratings read over the last games, as one quiet line.
struct RatingChart: View {
    let points: [Int]

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { g in
                let lo = Double((points.min() ?? 0) - 20), hi = Double((points.max() ?? 0) + 20)
                let y = { (v: Int) in g.size.height * (1 - (Double(v) - lo) / max(1, hi - lo)) }
                let x = { (i: Int) in g.size.width * Double(i) / Double(max(1, points.count - 1)) }
                Path { p in
                    for (i, v) in points.enumerated() { i == 0 ? p.move(to: CGPoint(x: x(i), y: y(v))) : p.addLine(to: CGPoint(x: x(i), y: y(v))) }
                }
                .stroke(Z.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let last = points.last {
                    Circle().fill(Z.ink).frame(width: 8, height: 8).position(x: x(points.count - 1), y: y(last))
                }
            }
            .frame(height: 110)
            HStack {
                Text(points.count >= RatingBook.chartLength ? "\(RatingBook.chartLength) games ago" : "Earlier")
                Spacer()
                Text("Now")
            }
            .font(Z.text(12.5)).foregroundStyle(Z.dim)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Your rating over your last rated games, from \(String(points.first ?? 0)) to \(String(points.last ?? 0))."))
    }
}
