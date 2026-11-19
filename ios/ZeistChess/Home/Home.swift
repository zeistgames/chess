import SwiftUI

/// What Play starts: the engine, the side, and the difficulty. Remembered between games.
enum Pick {
    static let engineKey = "pick.engine", sideKey = "pick.side", manualKey = "pick.manual", levelKey = "pick.level", ratedKey = "pick.rated", ratingKey = "pick.rating"
    static let timeKey = "pick.time", minutesKey = "pick.minutes", incrementKey = "pick.increment"
    /// A position to start from (FEN), empty for the usual start, and its name if it has one.
    static let startKey = "pick.start", startNameKey = "pick.startName"

    /// The clock chosen in the picker, or nil for no clock.
    static func timeControl(_ code: String, minutes: Int, increment: Int) -> TimeControl? {
        if code == "custom" { return .minutes(minutes, increment) }
        return TimeControl(pgn: code)
    }
    enum Side: String, Hashable, CaseIterable { case white, black, either
        var name: String { switch self { case .white: "White"; case .black: "Black"; case .either: "Either" } }
    }
}

/// Home: a board, set up and waiting (or your game in progress), the opponent and difficulty under it, and Play.
/// Settings is behind the profile button at the top right, as in Zeist. Settings is where engines are managed.
struct Home: View {
    @Binding var path: [Route]
    @State private var shelf = Shelf.shared
    @State private var log = GameLog.shared
    @State private var account = Account.shared
    @State private var session = Session.shared
    @AppStorage(Pick.engineKey) private var engineID = Shelf.bundledID
    @AppStorage(Pick.sideKey) private var side: Pick.Side = .either
    @AppStorage(Pick.manualKey) private var manual = false
    @AppStorage(Pick.levelKey) private var level = 3
    @AppStorage(Pick.ratedKey) private var rated = false
    @AppStorage(Pick.ratingKey) private var rating = 1500
    @AppStorage(Pick.timeKey) private var time = ""
    @AppStorage(Pick.minutesKey) private var customMinutes = 10
    @AppStorage(Pick.incrementKey) private var customIncrement = 5
    @AppStorage(Pick.startKey) private var start = ""
    @AppStorage(Pick.startNameKey) private var startName = ""
    private var timeControl: TimeControl? { Pick.timeControl(time, minutes: customMinutes, increment: customIncrement) }
    /// With Either chosen, the side for the next game is drawn here, before the board is shown, so the board on
    /// Home already faces the way the game will. Drawn again once that game has begun.
    @State private var drawn = Bool.random() ? "w" : "b"
    private var nextSide: String { switch side { case .white: "w"; case .black: "b"; case .either: drawn } }
    @State private var picking = false
    /// Set when the picker changes while a game is in progress: Play then starts a fresh game.
    @State private var fresh = false
    @State private var starting = false
    @State private var problem: String?
    @State private var levelNow = 2
    @Environment(\.horizontalSizeClass) private var size
    @Environment(\.scenePhase) private var phase
    /// The board sets itself up once per launch, never again.
    private static var setUpDone = false
    @State private var setUp = !Home.setUpDone
    @AppStorage("onboarded") private var onboarded = false

    private var engine: Engine? {
        shelf.engine(engineID).flatMap { $0.installed ? $0 : nil } ?? shelf.engine(Shelf.bundledID)
    }
    private var current: GameRecord? { fresh ? nil : log.current.flatMap { shelf.engine($0.engineID)?.installed == true ? $0 : nil } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 12)
            board
            caption
            Spacer(minLength: 20)
            VStack(spacing: 12) {
                picker
                Button(starting ? "Starting" : current != nil ? "Continue" : "Play") { Task { await play() } }
                    .buttonStyle(Pill(solid: true, wide: true))
                    .disabled(starting || engine == nil)
                    .accessibilityIdentifier("play")
                if let problem { Text(problem).font(Z.text(14)).foregroundStyle(Z.soft) }
            }
            .frame(maxWidth: 460)
            .padding(.horizontal, 24)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Z.ground.ignoresSafeArea())
        .foregroundStyle(Z.ink)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $picking, onDismiss: { Task { await refreshLevel() } }) {
            PickerSheet(engineID: $engineID, side: $side, manual: $manual, level: $level, rated: $rated, rating: $rating,
                        time: $time, customMinutes: $customMinutes, customIncrement: $customIncrement, start: $start, startName: $startName,
                        gameInProgress: log.current,
                        changed: { if log.current != nil { fresh = true } },
                        more: { picking = false; session.settingsAt = "engines"; session.openSettings = true })
        }
        .task {
            shelf.refresh()
            await refreshLevel()
        }
        .onAppear {
            fresh = false
            settle()
        }
        .onChange(of: onboarded) { _, _ in settle(); Task { await refreshLevel() } }
        .onChange(of: phase) { _, p in if p == .active { shelf.refresh() } }
        .onChange(of: engineID) { _, _ in Task { await refreshLevel() } }
        .onChange(of: session.openPicker) { _, open in if open { picking = true; session.openPicker = false } }
    }

    /// After the board has set itself up once (behind onboarding, it waits), it stays still for the rest of the launch.
    private func settle() {
        guard onboarded, setUp else { return }
        Task {
            try? await Task.sleep(for: .seconds(3))
            Home.setUpDone = true
        }
    }

    private func refreshLevel() async {
        guard let e = engine else { return }
        levelNow = await GameModel.startingLevel(e.id)
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ChessMark().frame(width: 27, height: 27).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                Text("Zeist").font(Z.title(32, relativeTo: .title))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Zeist Chess")
            .accessibilityAddTraits(.isHeader)
            Spacer()
            ProfileButton()
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    private var board: some View {
        let fen = current?.fen ?? (start.isEmpty ? GameModel.standardStart : start)
        let flipped = current.map { $0.player == "b" } ?? (nextSide == "b")
        return BoardStill(fen: fen, flipped: flipped, last: current?.moves.last, setUp: setUp && !Home.setUpDone && current == nil)
            .id(fen + (flipped ? "b" : "w") + (onboarded ? "o" : ""))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Z.ink.opacity(0.16), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 24, y: 18)
            // Touching a piece of yours begins the game with that piece picked up; anywhere else just begins it.
            .overlay(GeometryReader { g in
                Color.clear.contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded { e in
                    let cell = g.size.width / 8
                    var col = min(7, max(0, Int(e.location.x / cell))), row = min(7, max(0, Int(e.location.y / cell)))
                    if flipped { col = 7 - col; row = 7 - row }
                    Task { await play(select: row * 8 + col) }
                })
            })
            .padding(.horizontal, size == .regular ? 60 : 10)
            .frame(maxWidth: 640)
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(current != nil ? "Your game in progress" : "The board, set up")
            .accessibilityHint(current != nil ? "Continues the game" : "Starts a game")
    }

    /// One quiet line under the board: whose game this is.
    private var caption: some View {
        Group {
            if let g = current {
                Text("Your game against \(g.engineName), move \(g.moves.count / 2 + 1).")
            } else if fresh, let g = log.current {
                Button { fresh = false; Feel.shared.select() } label: { Text("Back to your game against \(g.engineName)").underline() }
                    .buttonStyle(.plain)
            } else if !start.isEmpty {
                Text("From \(startName.isEmpty ? "your position" : startName.prefix(1).lowercased() + startName.dropFirst()).")
            } else {
                Text(nextSide == "w" ? "Make the first move." : "Tap the board to begin.")
            }
        }
        .font(Z.text(14)).foregroundStyle(Z.dim).lineLimit(1).minimumScaleFactor(0.6)
        .padding(.top, 22).padding(.horizontal, 24)
    }

    private var picker: some View {
        let g = current
        let name = g?.engineName ?? engine?.name ?? "Stockfish Lite"
        let detail: String = {
            if let g { return "\(g.player == "w" ? "White" : "Black"). \(g.adaptive ? "Adaptive, level \(g.level)" : g.difficulty).\(g.timeControl.map { " \($0.name)." } ?? "")" }
            let clock = timeControl.map { " \($0.name)." } ?? ""
            if manual, rated, let r = engine?.manifest.ratings { return "\(side.name). Rating \(min(r.upperBound, max(r.lowerBound, rating))).\(clock)" }
            return "\(side.name). \(manual ? "Level \(level)" : "Adaptive, level \(levelNow)").\(clock)"
        }()
        return Button { Feel.shared.select(); picking = true } label: {
            HStack(spacing: 12) {
                EngineFace(id: g?.engineID ?? engine?.id ?? Shelf.bundledID, name: name, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(Z.title(20, relativeTo: .title3)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(detail).font(Z.text(13.5)).foregroundStyle(Z.soft).lineLimit(1).minimumScaleFactor(0.6)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 13, weight: .medium)).foregroundStyle(Z.dim)
            }
            .padding(.leading, 12).padding(.trailing, 20).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Capsule().fill(Z.raised))
            .overlay(Capsule().strokeBorder(Z.hair, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(Press())
        .accessibilityLabel("\(name). \(detail) Change")
        .accessibilityIdentifier("picker")
    }

    // MARK: Play

    private func play(select: Int? = nil) async {
        guard !starting else { return }
        problem = nil
        if let g = current, let e = shelf.engine(g.engineID) {
            Feel.shared.select()
            let m = GameModel(record: g, engine: e)
            Session.shared.game = m
            path.append(.game)
            if let select { Task { try? await Task.sleep(for: .seconds(0.5)); if m.canLift(select) { m.selected = select } } }
            return
        }
        guard let e = engine else { return }
        starting = true
        defer { starting = false }
        let color = nextSide
        let lvl = manual ? level : await GameModel.startingLevel(e.id)
        do {
            let m = try await GameModel.begin(engine: e, player: color, level: lvl, adaptive: !manual, rating: manual && rated ? rating : nil, time: timeControl,
                                              start: start.isEmpty ? GameModel.standardStart : start)
            Feel.shared.select()
            Session.shared.game = m
            fresh = false
            path.append(.game)
            if let select, m.canLift(select) { m.selected = select }
            drawn = Bool.random() ? "w" : "b"
        } catch {
            problem = "The game couldn't start. Try again."
            ReviewRequest.shared.record(.trouble)
        }
    }
}

/// A finished game in a list: when, against whom, the level, the result.
struct GameRow: View {
    let game: GameRecord

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(game.engineName).font(Z.medium(16)).lineLimit(1).minimumScaleFactor(0.6)
                Text("\(Fmt.short(game.startedAt)) · \(game.difficulty)\(game.timeControl.map { " · \($0.name)" } ?? "")\(game.learn == true ? " · Learn as you play" : "")")
                    .font(Z.text(13)).foregroundStyle(Z.dim).lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 8)
            Text(Self.word(game)).font(Z.text(15)).foregroundStyle(game.outcome == "win" ? Z.ink : Z.soft)
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    static func word(_ g: GameRecord) -> String {
        if g.ending == "abandoned" { return "Unfinished" }
        if g.ending == "resigned" { return "Resigned" }
        if g.ending == "timeout" { return g.outcome == "win" ? "Won on time" : "Lost on time" }
        if g.ending == "agreement" { return "Draw agreed" }
        if g.ending == "engine-resigned" { return "Engine resigned" }
        switch g.outcome {
        case "win": return "Won"
        case "loss": return "Lost"
        default: return "Draw"
        }
    }
}

/// A profile picture from Zeist, or the first letter of the username.
struct Avatar: View {
    let me: Account.Me?
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            Circle().fill(Z.raised)
            Text(String((me?.handle ?? "Z").prefix(1)).uppercased()).font(Z.medium(size * 0.42)).foregroundStyle(Z.ink)
            if let s = me?.picture, s.hasPrefix("https://"), let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Z.hair, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// The button at the top right of each place: your picture when signed in, a person when not. It opens your
/// account and Settings, as in the main Zeist app.
struct ProfileButton: View {
    @State private var account = Account.shared

    var body: some View {
        Button { Feel.shared.select(); Session.shared.openSettings = true } label: {
            Group {
                if account.signedIn { Avatar(me: account.me, size: 40) }
                else {
                    Image(systemName: "person")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Z.soft)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Z.faint))
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(Press())
        .accessibilityLabel("Account and settings")
        .accessibilityIdentifier("profile")
    }
}

/// Numbers and dates in American English, whatever the phone's region.
enum Fmt {
    static let us = Locale(identifier: "en_US")
    static func short(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(locale: us).month(.abbreviated).day().hour().minute())
    }
    static func long(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: us))
    }
}

enum Bytes {
    static func say(_ n: Int) -> String {
        if n < 1_000_000 { return "\(max(1, n / 1000)) KB" }
        if n < 1_000_000_000 {
            let mb = Double(n) / 1_000_000
            return mb < 10 ? String(format: "%.1f MB", mb) : "\(Int(mb.rounded())) MB"
        }
        return String(format: "%.1f GB", Double(n) / 1_000_000_000)
    }
}
