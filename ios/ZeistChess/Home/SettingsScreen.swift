import SwiftUI

/// Settings: your account, the board (theme, pieces, size, coordinates), the engines (download, delete, who made them), play, your games, the source.
struct SettingsScreen: View {
    @State private var shelf = Shelf.shared
    @AppStorage("sound") private var sound = true
    @AppStorage("haptics") private var haptics = true
    @AppStorage(Feel.weightKey) private var weight = Feel.weightDefault
    @AppStorage(GameModel.queenKey) private var autoQueen = false
    @AppStorage(GameModel.humanKey) private var humanMode = false
    @AppStorage(GameModel.paceKey) private var pace = true
    @AppStorage(Measure.key) private var measure = true
    #if DEBUG
    @State private var reviewForced = false
    #endif
    @AppStorage(EngineGames.key) private var shareGames = EngineGames.startsOn
    @State private var center = GameCenter.shared
    @AppStorage(Look.key) private var themeID = Themes.file.default
    @AppStorage(Look.piecesKey) private var piecesID = PieceSets.file.default
    @AppStorage(Look.coordinatesKey) private var coordinates = true
    @AppStorage(Look.edgeKey) private var edge = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var type
    private var big: Bool { type.isAccessibilitySize }

    var body: some View {
        ScrollViewReader { reader in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings").font(Z.title(34)).padding(.top, 14)

                section("Zeist account")
                AccountPanel()

                // Everything about how the board looks, in one place.
                section("Board")
                themes
                pieceSets.padding(.top, 18)
                VStack(spacing: 0) {
                    (big ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))) {
                        Text("Size").font(Z.text(16))
                        if !big { Spacer(minLength: 8) }
                        Choice(options: [(false, "Inset"), (true, "Edge to edge")], value: $edge, height: 34)
                            .frame(maxWidth: big ? .infinity : 230)
                            .accessibilityIdentifier("board-size")
                    }
                    .padding(.vertical, 10)
                    rule
                    toggle("Coordinates", $coordinates).accessibilityIdentifier("coordinates")
                }
                .padding(.top, 18)

                Text("Engines").zLabel().padding(.top, 34).padding(.bottom, 4).id("engines")
                VStack(spacing: 0) {
                    ForEach(shelf.engines) { e in
                        EngineRow(engine: e)
                        if e.id != shelf.engines.last?.id { rule }
                    }
                }
                HStack {
                    Text("Downloaded engines").font(Z.text(15)).foregroundStyle(Z.soft)
                    Spacer()
                    let used = shelf.storageUsed()
                    Text(used < 10_000 ? "None yet" : Bytes.say(used)).font(Z.text(15)).monospacedDigit()
                }
                .padding(.top, 14)
                .accessibilityElement(children: .combine)

                section("Play")
                VStack(spacing: 0) {
                    toggle("Sound", $sound)
                    rule
                    toggle("Haptics", $haptics)
                    if haptics {
                        HStack(spacing: 12) {
                            Text("Light").font(Z.text(13.5)).foregroundStyle(Z.soft)
                            Slider(value: $weight, in: 0...1, step: 0.1) { editing in if !editing { Feel.shared.move(capture: false) } }
                                .tint(Z.amber).accessibilityLabel("How heavy the pieces feel").accessibilityIdentifier("haptic-weight")
                            Text("Heavy").font(Z.text(13.5)).foregroundStyle(Z.soft)
                        }
                        .padding(.bottom, 10)
                    }
                    rule
                    toggle("Engines take their time", $pace).accessibilityIdentifier("engine-pace")
                    rule
                    toggle("Always promote to a queen", $autoQueen).accessibilityIdentifier("auto-queen")
                    rule
                    toggle("Human mode", $humanMode).accessibilityIdentifier("human-mode")
                    Text("A badly beaten engine may ask for a draw, or resign, the way a person would.")
                        .font(Z.text(13.5)).foregroundStyle(Z.soft).frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true).padding(.bottom, 8)
                }

                section("Your games")
                Text("Every game is kept on this iPhone. Export them all as PGN, which any chess app reads, or as JSON with every detail.")
                    .font(Z.text(14.5)).foregroundStyle(Z.soft).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if let pgn = try? GameLog.shared.exportPGN() { ShareLink("PGN", item: pgn).buttonStyle(Pill(small: true)) }
                    if let json = try? GameLog.shared.exportJSON() { ShareLink("JSON", item: json).buttonStyle(Pill(small: true)) }
                }
                .padding(.top, 12)

                if center.signedIn {
                    section("Achievements")
                    Button("Open in Game Center") { GameCenter.shared.show() }.buttonStyle(Pill(small: true)).padding(.top, 4)
                        .accessibilityIdentifier("achievements")
                }

                section("Privacy")
                VStack(alignment: .leading, spacing: 0) {
                    toggle("Share usage with Zeist", $measure).accessibilityIdentifier("measure")
                        .onChange(of: measure) { _, _ in Measure.apply() }
                    Text("How often the app is opened, which engines and puzzles are played, and how games end, measured with Google Analytics so Zeist Chess can be made better. Never your moves, your name or an advertising identifier.")
                        .font(Z.text(13.5)).foregroundStyle(Z.dim).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                    rule.padding(.top, 12)
                    toggle("Share my games against the Zeist engine", $shareGames).accessibilityIdentifier("share-games")
                        .onChange(of: shareGames) { _, _ in EngineGames.apply() }
                    Text("To help the Zeist engine play better. Only the game is sent: its moves, the level, the result and the clock. Nothing about you, and no account. Turn it off here at any time.")
                        .font(Z.text(13.5)).foregroundStyle(Z.dim).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                    if shareGames, EngineGames.say == .never {
                        Text("Your Zeist account has this turned off, so no games are sent.")
                            .font(Z.text(13.5)).foregroundStyle(Z.dim).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                            .accessibilityIdentifier("share-games-account-off")
                    }
                }

                section("About")
                VStack(alignment: .leading, spacing: 10) {
                    Text("Zeist Chess is open source under the GNU Affero General Public License, version 3 or later.")
                        .font(Z.text(14.5)).foregroundStyle(Z.soft).fixedSize(horizontal: false, vertical: true)
                    Link(destination: URL(string: "https://github.com/zeistgames/chess")!) {
                        Text("github.com/zeistgames/chess").font(Z.text(15)).underline()
                    }
                    Link("Rate Zeist Chess", destination: ReviewRequest.writeReview).buttonStyle(Pill(small: true))
                        .accessibilityIdentifier("rate")
                    #if DEBUG
                    Button(ReviewRequest.shared.forced ? "The next win asks for a rating" : "Debug: ask for a rating at the next win") {
                        ReviewRequest.shared.forceNext()
                        reviewForced.toggle()
                    }
                    .buttonStyle(Pill(small: true)).id(reviewForced)
                    #endif
                    VStack(alignment: .leading, spacing: 6) {
                        line("Rules", "chess.js by Jeff Hlywa. BSD-2-Clause.")
                        pieceCredits
                        line("Type", "Prata and Jost. SIL Open Font License 1.1.")
                    }
                    .padding(.top, 6)
                    Text("Version \(GameRecord.appVersion)").font(Z.text(13)).foregroundStyle(Z.dim).padding(.top, 6)
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        // Back stays put while the page scrolls, on the ground's own color so nothing runs under the status bar.
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                RoundIcon(symbol: "chevron.left", label: "Back") { dismiss() }
                Spacer()
            }
            .frame(maxWidth: 620).padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 6)
            .frame(maxWidth: .infinity)
            .background(Z.ground.ignoresSafeArea(edges: .top))
        }
        .task {
            // "More engines" in the picker opens Settings at its engines.
            guard Session.shared.settingsAt == "engines" else { return }
            Session.shared.settingsAt = nil
            try? await Task.sleep(for: .seconds(0.35))
            withAnimation(.easeInOut(duration: 0.35)) { reader.scrollTo("engines", anchor: .top) }
        }
        }
        .background(Z.ground.ignoresSafeArea())
        .foregroundStyle(Z.ink)
        .toolbar(.hidden, for: .navigationBar)
        .task { shelf.refresh() }
    }

    private var themes: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(Themes.all) { t in
                Button {
                    if themeID != t.id { themeID = t.id; Feel.shared.select() }
                } label: {
                    VStack(spacing: 8) {
                        ThemeSwatch(theme: t)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Z.ink.opacity(themeID == t.id ? 0.9 : 0.12), lineWidth: themeID == t.id ? 2 : 1).padding(themeID == t.id ? -4 : 0))
                        Text(t.name).font(Z.text(13)).foregroundStyle(themeID == t.id ? Z.ink : Z.soft)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(Press())
                .accessibilityLabel("\(t.name) board")
                .accessibilityAddTraits(themeID == t.id ? .isSelected : [])
                .accessibilityIdentifier("theme-\(t.id)")
            }
        }
        .padding(.top, 6)
        .animation(.easeOut(duration: 0.15), value: themeID)
    }

    private var pieceSets: some View {
        let theme = Themes.named(themeID)
        return HStack(alignment: .top, spacing: 14) {
            ForEach(PieceSets.all) { set in
                let on = PieceSets.named(piecesID).id == set.id
                Button {
                    if !on { piecesID = set.id; Feel.shared.select() }
                } label: {
                    VStack(spacing: 8) {
                        PieceSwatch(set: set.id, theme: theme)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Z.ink.opacity(on ? 0.9 : 0.12), lineWidth: on ? 2 : 1).padding(on ? -4 : 0))
                        Text(set.name).font(Z.text(13)).foregroundStyle(on ? Z.ink : Z.soft)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(Press())
                .accessibilityLabel("\(set.name) pieces")
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("pieces-\(set.id)")
            }
        }
        .padding(.top, 6)
        .animation(.easeOut(duration: 0.15), value: piecesID)
    }

    /// Who drew each piece set, its license and where it comes from.
    private var pieceCredits: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pieces").font(Z.medium(13.5))
            ForEach(PieceSets.all) { set in
                Text(credit(set)).font(Z.text(13.5)).foregroundStyle(Z.soft).tint(Z.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Each set is lit in ivory and ebony.").font(Z.text(13.5)).foregroundStyle(Z.soft)
        }
        .accessibilityElement(children: .contain)
    }

    private func credit(_ set: PieceSet) -> AttributedString {
        var s = AttributedString("\(set.name), by \(set.author). \(set.license). ")
        var link = AttributedString("Source")
        link.link = URL(string: set.source)
        link.underlineStyle = .single
        s.append(link)
        return s
    }

    private var rule: some View { Rectangle().fill(Z.hair).frame(height: 1) }

    private func section(_ title: String) -> some View {
        Text(title).zLabel().padding(.top, 34).padding(.bottom, 12)
    }

    private func toggle(_ title: String, _ value: Binding<Bool>) -> some View {
        Toggle(title, isOn: value).font(Z.text(16)).tint(Z.amber).padding(.vertical, 8)
    }

    private func line(_ what: String, _ detail: String) -> some View {
        (Text(what + "  ").font(Z.medium(13.5)) + Text(detail).font(Z.text(13.5)).foregroundColor(Z.soft))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A corner of a board in a theme: four by four squares, with an ivory and an ebony piece.
struct ThemeSwatch: View {
    let theme: BoardTheme

    var body: some View {
        GeometryReader { geo in
            let cell = geo.size.width / 4
            ZStack(alignment: .topLeading) {
                BoardGround(theme: theme).equatable().frame(width: cell * 8, height: cell * 8)
                PieceImage(piece: "bN").frame(width: cell * 0.9, height: cell * 0.9).frame(width: cell, height: cell).offset(x: cell * 1, y: cell * 1)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                PieceImage(piece: "wP").frame(width: cell * 0.9, height: cell * 0.9).frame(width: cell, height: cell).offset(x: cell * 2, y: cell * 2)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
            }
            .frame(width: geo.size.width, height: geo.size.width, alignment: .topLeading)
            .clipped()
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Two squares of the board in use, a dark and a light, with an ivory king and an ebony knight in one piece set.
struct PieceSwatch: View {
    let set: String
    let theme: BoardTheme

    var body: some View {
        GeometryReader { geo in
            let cell = geo.size.width / 2
            ZStack(alignment: .topLeading) {
                // Columns b and c of the top rank: a dark square, then a light one.
                BoardGround(theme: theme).equatable().frame(width: cell * 8, height: cell * 8).offset(x: -cell)
                PieceImage(piece: "wK", set: set).frame(width: cell * 0.86, height: cell * 0.86).frame(width: cell, height: cell)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                PieceImage(piece: "bN", set: set).frame(width: cell * 0.86, height: cell * 0.86).frame(width: cell, height: cell).offset(x: cell)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
            }
            .frame(width: geo.size.width, height: cell, alignment: .topLeading)
            .clipped()
        }
        .aspectRatio(2, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// One engine: its name and short line, its license, size and source, and Download, progress, or Delete.
struct EngineRow: View {
    let engine: Engine
    @State private var shelf = Shelf.shared
    @State private var deleting = false
    @Environment(\.dynamicTypeSize) private var type
    private var big: Bool { type.isAccessibilitySize }

    var body: some View {
        let e = engine, m = e.manifest
        let state = shelf.downloads[e.id]
        (big ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .center, spacing: 14))) {
            if !big { EngineFace(id: e.id, name: m.name, size: 38) }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(m.name).font(Z.title(19, relativeTo: .headline)).lineLimit(1).minimumScaleFactor(0.75)
                    if m.version.count <= 9 { Text(m.version).font(Z.text(12)).foregroundStyle(Z.dim).lineLimit(1) }
                }
                if let line = m.line { Text(line).font(Z.text(14)).foregroundStyle(Z.soft).lineLimit(2).truncationMode(.tail).fixedSize(horizontal: false, vertical: true) }
                HStack(spacing: 5) {
                    Text(size).lineLimit(1)
                    if let s = m.source, let url = URL(string: s) {
                        Text("·")
                        Link(destination: url) { Text("Source").underline() }
                    }
                }
                .font(Z.text(12.5)).foregroundStyle(Z.dim)
                if let l = m.license {
                    Text(l.replacingOccurrences(of: " AND ", with: ", ")).font(Z.text(12.5)).foregroundStyle(Z.dim)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                if case .failed(let why) = state {
                    Text("\(why) Try again.").font(Z.text(13)).foregroundStyle(Z.soft)
                }
            }
            if !big { Spacer(minLength: 4) }
            action(e, state)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
    }

    private var size: String {
        let e = engine
        if e.bundled { return "Built in" }
        if e.installed { return "\(Bytes.say(shelf.size(of: e.id))) on this iPhone" }
        return Bytes.say(e.manifest.downloadBytes)
    }

    @ViewBuilder private func action(_ e: Engine, _ state: Download?) -> some View {
        switch state {
        case .running(let p):
            Button { shelf.cancel(e.id) } label: {
                ZStack {
                    Circle().stroke(Z.hair, lineWidth: 2.5)
                    Circle().trim(from: 0, to: max(0.02, p)).stroke(Z.ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.2), value: p)
                    Image(systemName: "stop.fill").font(.system(size: 9)).foregroundStyle(Z.soft)
                }
                .frame(width: 34, height: 34).padding(4).contentShape(Rectangle())
            }
            .buttonStyle(Press())
            .accessibilityLabel("Downloading, \(Int(p * 100)) percent. Stop")
        case .failed:
            Button("Retry") { shelf.clearFailure(e.id); shelf.download(e.id) }.buttonStyle(Pill(small: true))
        case nil:
            if e.bundled {
                EmptyView()
            } else if e.installed {
                Button("Delete") { deleting = true }
                    .font(Z.text(14.5)).foregroundStyle(Z.soft).buttonStyle(.plain).padding(.horizontal, 6).frame(minHeight: 36)
                    .accessibilityIdentifier("delete-\(e.id)")
                    .confirmationDialog("Delete \(e.name)?", isPresented: $deleting, titleVisibility: .visible) {
                        Button("Delete", role: .destructive) { shelf.delete(e.id) }
                        Button("Keep", role: .cancel) {}
                    } message: {
                        Text("It frees \(Bytes.say(shelf.size(of: e.id))). You can download it again."
                             + (GameLog.shared.current?.engineID == e.id ? " Your game against it ends here and stays in Games." : ""))
                    }
            } else {
                Button("Download") { Feel.shared.select(); shelf.download(e.id) }.buttonStyle(Pill(small: true))
                    .disabled(Places.packsURL == nil)
                    .accessibilityIdentifier("download-\(e.id)")
            }
        }
    }
}

/// Signed out: one quiet line and Sign in. Signed in: who you are, and Sign out.
struct AccountPanel: View {
    @State private var account = Account.shared
    @State private var confirmOut = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var deleteFailed = false

    var body: some View {
        if account.signedIn {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Avatar(me: account.me, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.me?.display_name ?? account.handle ?? "Signed in").font(Z.medium(17)).lineLimit(1)
                        if let h = account.handle { Text("@\(h)").font(Z.text(14)).foregroundStyle(Z.soft).lineLimit(1) }
                        else { Text("Choose a username on \(Hosts.primary).").font(Z.text(14)).foregroundStyle(Z.soft) }
                    }
                    Spacer()
                    Button("Sign out") { confirmOut = true }
                        .buttonStyle(Pill(small: true))
                        .disabled(deleting)
                        .confirmationDialog("Sign out of Zeist?", isPresented: $confirmOut, titleVisibility: .visible) {
                            Button("Sign out", role: .destructive) { Task { await account.signOut() } }
                            Button("Stay signed in", role: .cancel) {}
                        } message: { Text("Your games stay on this iPhone.") }
                }
                Text("Your games are kept on this iPhone under your account. Ratings and records come in a later version.")
                    .font(Z.text(13.5)).foregroundStyle(Z.dim).fixedSize(horizontal: false, vertical: true)
                Button {
                    confirmDelete = true
                } label: {
                    Text(deleting ? "Deleting your account" : "Delete your account").font(Z.text(14.5)).underline()
                        .foregroundStyle(Z.soft).frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(deleting)
                .accessibilityIdentifier("delete-account")
                .confirmationDialog("Delete your Zeist account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete account", role: .destructive) {
                        deleting = true
                        Task {
                            let done = await account.delete()
                            deleting = false
                            deleteFailed = !done && account.signedIn
                            if deleteFailed { ReviewRequest.shared.record(.trouble) }
                        }
                    }
                    Button("Keep it", role: .cancel) {}
                } message: {
                    Text("This deletes your whole Zeist account, in Zeist as well as here: your username, games, ratings, follows and picture. You are signed out everywhere. It can't be undone. Games kept on this iPhone stay.")
                }
                .alert("That didn't work.", isPresented: $deleteFailed) {
                    Button("OK", role: .cancel) {}
                } message: { Text("Your account was not deleted. Check your connection and try again.") }
            }
        } else {
            SignInLine()
        }
    }
}
