import SwiftUI

/// Who to play and how: the engines on this iPhone, the side, and the difficulty. Changes are kept for next time.
struct PickerSheet: View {
    @Binding var engineID: String
    @Binding var side: Pick.Side
    @Binding var manual: Bool
    @Binding var level: Int
    @Binding var rated: Bool
    @Binding var rating: Int
    @Binding var time: String
    @Binding var customMinutes: Int
    @Binding var customIncrement: Int
    @Binding var start: String
    @Binding var startName: String
    /// A rated game against the Zeist engine (Rated), and its level: 0 for Matched.
    @Binding var ratedGame: Bool
    @Binding var ratedLevel: Int
    let gameInProgress: GameRecord?
    let changed: () -> Void
    let more: () -> Void
    @State private var shelf = Shelf.shared
    @State private var adaptiveAt = 1
    @State private var positioning = false
    @State private var account = Account.shared
    @State private var book = RatingBook.shared
    /// The next game is rated: the Zeist engine, an account, and Rated on.
    private var ratedNext: Bool { ratedGame && engineID == Rated.engineID && account.signedIn }
    @Environment(\.dismiss) private var dismiss

    private var installed: [Engine] { shelf.engines.filter(\.installed) }
    private enum Mode: Hashable { case adaptive, level, rating }
    /// The ratings the chosen engine can be set to, when it has that setting.
    private var ratings: ClosedRange<Int>? { shelf.engine(engineID)?.manifest.ratings }
    private var mode: Mode { !manual ? .adaptive : (rated && ratings != nil ? .rating : .level) }
    private func set(_ m: Mode) {
        manual = m != .adaptive
        if m != .adaptive { rated = m == .rating }
        if m == .rating, let r = ratings { rating = min(r.upperBound, max(r.lowerBound, rating)) }
        changed()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Opponent").zLabel().padding(.bottom, 8)
                VStack(spacing: 0) {
                    ForEach(installed) { e in
                        Button {
                            if engineID != e.id { engineID = e.id; changed(); Feel.shared.select() }
                        } label: { row(e) }
                        .buttonStyle(Press())
                        .accessibilityIdentifier("pick-\(e.id)")
                        .accessibilityAddTraits(engineID == e.id ? .isSelected : [])
                        Rectangle().fill(Z.hair).frame(height: 1)
                    }
                    Button(action: more) {
                        HStack {
                            Text("More engines").font(Z.text(15.5)).foregroundStyle(Z.soft)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Z.dim)
                        }
                        .padding(.vertical, 14).contentShape(Rectangle())
                    }
                    .buttonStyle(Press())
                    .accessibilityIdentifier("more-engines")
                }

                Text("Play as").zLabel().padding(.top, 26).padding(.bottom, 10)
                Choice(options: Pick.Side.allCases.map { ($0, $0.name) }, value: Binding(get: { side }, set: { side = $0; changed() }))

                Text("Difficulty").zLabel().padding(.top, 26).padding(.bottom, 10)
                if ratedNext { ratedDifficulty } else {
                Choice(options: [(Mode.adaptive, "Adaptive"), (Mode.level, "Level")] + (ratings == nil ? [] : [(Mode.rating, "Rating")]),
                       value: Binding(get: { mode }, set: { set($0) }))
                Group {
                    switch mode {
                    case .adaptive:
                        Text("Level \(adaptiveAt) of 10. It moves up when you win and down when you lose, quickly at first.")
                            .font(Z.text(13.5)).foregroundStyle(Z.soft).fixedSize(horizontal: false, vertical: true)
                    case .level:
                        LevelRow(level: Binding(get: { level }, set: { level = $0; changed() }))
                    case .rating:
                        if let r = ratings { RatingRow(rating: Binding(get: { min(r.upperBound, max(r.lowerBound, rating)) }, set: { rating = $0; changed() }), range: r, human: engineID == "maia") }
                    }
                }
                .padding(.top, 14)
                .transition(.opacity)
                }
                RatedRow(on: $ratedGame, zeist: engineID == Rated.engineID, changed: changed).padding(.top, 22)

                if !ratedNext {
                Text("Time").zLabel().padding(.top, 26).padding(.bottom, 10)
                TimeChoice(time: Binding(get: { time }, set: { time = $0; changed() }),
                           minutes: Binding(get: { customMinutes }, set: { customMinutes = $0; changed() }),
                           increment: Binding(get: { customIncrement }, set: { customIncrement = $0; changed() }))
                Button { positioning = true } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("From a position").font(Z.text(15.5)).foregroundStyle(Z.soft)
                            if !start.isEmpty {
                                Text(startName.isEmpty ? "Your position" : startName).font(Z.text(13)).foregroundStyle(Z.dim).lineLimit(1)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Z.dim)
                    }
                    .padding(.vertical, 14).contentShape(Rectangle())
                }
                .buttonStyle(Press())
                .overlay(alignment: .top) { Rectangle().fill(Z.hair).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(Z.hair).frame(height: 1) }
                .padding(.top, 26)
                .accessibilityIdentifier("from-position")
                .sheet(isPresented: $positioning) {
                    PositionSheet(start: Binding(get: { start }, set: { start = $0; changed() }), startName: $startName,
                                  side: Binding(get: { side }, set: { side = $0; changed() }))
                }
                }
                if let g = gameInProgress {
                    Text(g.isRated ? "Starting another game resigns your rated game against \(g.engineName)." : "Your game against \(g.engineName) stays until you start another.")
                        .font(Z.text(13.5)).foregroundStyle(Z.dim).padding(.top, 20)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Done") { dismiss() }.buttonStyle(Pill(wide: true)).padding(.top, 26)
            }
            .padding(.horizontal, 24).padding(.top, 30).padding(.bottom, 16)
            .animation(.easeOut(duration: 0.2), value: mode)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(Z.ink)
        .presentationBackground(Z.raised)
        .presentationDetents([.large])
        .presentationCornerRadius(30)
        .presentationDragIndicator(.visible)
        .task(id: engineID) { adaptiveAt = await GameModel.startingLevel(engineID) }
        .task(id: ratedNext) { if ratedNext { await book.refresh() } }
        .animation(.easeOut(duration: 0.2), value: ratedNext)
    }

    /// Rated: Matched (Zeist picks the level nearest the rating) or one of Zeist's eight levels, with its rating.
    private var ratedDifficulty: some View {
        VStack(alignment: .leading, spacing: 14) {
            Choice(options: [(0, "Matched"), (1, "Level")], value: Binding(get: { ratedLevel == 0 ? 0 : 1 }, set: { v in
                ratedLevel = v == 0 ? 0 : min(8, max(1, book.current?.level ?? 3)); changed()
            }))
            if ratedLevel != 0 {
                LevelRow(level: Binding(get: { ratedLevel }, set: { ratedLevel = $0; changed() }), top: 8)
            }
            Text(ratedNote).font(Z.text(13.5)).foregroundStyle(Z.soft).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("rated-note")
        }
    }

    private var ratedNote: String {
        let s = book.current
        if ratedLevel != 0 { return "Level \(ratedLevel), rated \(Rated.rating(ofLevel: ratedLevel) ?? 0)." }
        guard let l = s?.level, let lr = Rated.rating(ofLevel: l) else { return "Zeist picks the level nearest your rating, so you win about half your games." }
        if let r = s?.rating { return "Level \(l), rated \(lr), the nearest to your rating of \(r)." }
        return "Level \(l), rated \(lr), for your first rated games."
    }

    private func row(_ e: Engine) -> some View {
        HStack(spacing: 12) {
            EngineFace(id: e.id, name: e.name, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(e.name).font(Z.title(19, relativeTo: .headline)).lineLimit(1).minimumScaleFactor(0.7)
                if let line = e.manifest.line { Text(line).font(Z.text(13.5)).foregroundStyle(Z.soft).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Z.ink).opacity(engineID == e.id ? 1 : 0)
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

/// Levels 1 to 10, one tap each.
struct LevelRow: View {
    @Binding var level: Int
    var top = 10

    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...top, id: \.self) { n in
                Button {
                    if level != n { level = n; Feel.shared.select() }
                } label: {
                    Text("\(n)").font(Z.medium(15))
                        .foregroundStyle(level == n ? Z.ground : Z.soft)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(Circle().fill(level == n ? Z.ink : .clear).frame(width: 34, height: 34))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Level \(n)")
                .accessibilityAddTraits(level == n ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Z.faint))
        .animation(.spring(duration: 0.28), value: level)
    }
}

/// A rating set by hand, for engines that take one. The number is the engine's own, in steps of 50.
struct RatingRow: View {
    @Binding var rating: Int
    let range: ClosedRange<Int>
    let human: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: String(rating)).font(Z.title(26, relativeTo: .title2)).monospacedDigit().contentTransition(.numericText())
                Spacer()
                Text(verbatim: "\(String(range.lowerBound)) to \(String(range.upperBound))").font(Z.text(13.5)).foregroundStyle(Z.dim)
            }
            Slider(value: Binding(get: { Double(rating) }, set: { v in
                let n = min(range.upperBound, max(range.lowerBound, Int((v / 50).rounded()) * 50))
                if n != rating { rating = n; Feel.shared.select() }
            }), in: Double(range.lowerBound)...Double(range.upperBound))
            .tint(Z.amber)
            .accessibilityLabel("Rating")
            .accessibilityValue("\(rating)")
            .accessibilityIdentifier("rating")
            Text(human ? "Plays like people at this rating." : "On this engine's own scale, not a human rating.")
                .font(Z.text(13.5)).foregroundStyle(Z.soft).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// No clock (the default), the standard controls grouped as bullet, blitz and rapid, or minutes and increment of
/// your own. Stored as "" for no clock, "custom", or a control's PGN form ("180+2").
struct TimeChoice: View {
    @Binding var time: String
    @Binding var minutes: Int
    @Binding var increment: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            line(nil, [("", "No clock")])
            ForEach(TimeControl.presets, id: \.0) { kind, controls in
                line(kind.name, controls.map { ($0.pgn, $0.name) })
            }
            line("Custom", [("custom", TimeControl.minutes(minutes, increment).name)])
            if time == "custom" {
                VStack(spacing: 0) {
                    Counter(title: "Minutes", value: $minutes, range: 1...180, id: "minutes")
                    Rectangle().fill(Z.hair).frame(height: 1)
                    Counter(title: "Seconds added per move", value: $increment, range: 0...60, id: "increment")
                }
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: time == "custom")
    }

    private func line(_ label: String?, _ options: [(String, String)]) -> some View {
        HStack(spacing: 6) {
            Text(label ?? "").font(Z.text(13)).foregroundStyle(Z.dim).frame(width: 52, alignment: .leading).accessibilityHidden(true)
            ForEach(options, id: \.0) { code, name in
                let on = time == code
                Button {
                    if !on { time = code; Feel.shared.select() }
                } label: {
                    Text(name).font(Z.medium(14)).lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(on ? Z.ground : Z.soft)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(Capsule().fill(on ? Z.ink : Z.faint))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label.map { "\($0), \(name)" } ?? name)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("time-\(code.isEmpty ? "none" : code)")
            }
            if options.count < 4 { ForEach(0..<(4 - options.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 1) } }
        }
        .animation(.easeOut(duration: 0.15), value: time)
    }
}

/// A number with minus and plus, for the custom clock.
struct Counter: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let id: String

    var body: some View {
        HStack(spacing: 14) {
            Text(title).font(Z.text(15)).foregroundStyle(Z.soft)
            Spacer(minLength: 8)
            button("minus", value > range.lowerBound) { value -= 1 }
            Text("\(value)").font(Z.medium(16)).monospacedDigit().frame(minWidth: 30)
                .contentTransition(.numericText())
            button("plus", value < range.upperBound) { value += 1 }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { d in
            if d == .increment, value < range.upperBound { value += 1 }
            if d == .decrement, value > range.lowerBound { value -= 1 }
        }
        .accessibilityIdentifier(id)
    }

    private func button(_ symbol: String, _ enabled: Bool, _ act: @escaping () -> Void) -> some View {
        Button { act(); Feel.shared.select() } label: {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                .frame(width: 34, height: 34).background(Circle().fill(Z.faint)).contentShape(Circle())
        }
        .buttonStyle(Press())
        .foregroundStyle(Z.ink)
        .opacity(enabled ? 1 : 0.3)
        .disabled(!enabled)
        .accessibilityIdentifier("\(id)-\(symbol)")
    }
}
