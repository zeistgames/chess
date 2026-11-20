import SwiftUI

/// Shown once: the mark and name, how well you play, which engines to download, and signing in. Skippable at every
/// step; it ends on the Home board.
struct Onboarding: View {
    let done: () -> Void

    enum Step: Int, CaseIterable { case hello, level, engines, account }
    @State private var step: Step = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-onboarding-last") { return .account }
        if let n = Debug.value("-onboarding-step").flatMap({ Int($0) }), let s = Step(rawValue: n) { return s }
        #endif
        return .hello
    }()
    @State private var forward = true
    @State private var level: Int?
    @State private var chosen: Set<String> = []
    @State private var shelf = Shelf.shared
    @State private var account = Account.shared
    @State private var signingIn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    static let answers: [(String, String, Int)] = [
        ("Learning", "I'm learning how the pieces move.", 1),
        ("Now and then", "I know the rules and play now and then.", 3),
        ("Often", "I play often and know some openings.", 5),
        ("Rated", "I play rated games, online or at a club.", 7),
    ]

    /// A short screen (a small iPhone, the closed Duo): the pages give up spare room so nothing is pushed off.
    @State private var tight = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if step != .account {
                    Button { finish() } label: {
                        Text("Skip").font(Z.text(15.5)).foregroundStyle(Z.soft)
                            .frame(minWidth: 44, minHeight: 44, alignment: .trailing).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("skip")
                }
            }
            .frame(height: 44)
            .padding(.horizontal, 24).padding(.top, 6)
            ZStack {
                page.id(step)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .offset(x: forward ? 36 : -36).combined(with: .opacity),
                        removal: .offset(x: forward ? -24 : 24).combined(with: .opacity)))
            }
            .frame(maxWidth: 520, maxHeight: .infinity)
            .padding(.horizontal, 24)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: Bool.self) { $0.size.height < 700 } action: { tight = $0 }
        .background(Z.ground.ignoresSafeArea())
        .foregroundStyle(Z.ink)
        .task { shelf.refresh() }
        .sheet(isPresented: $signingIn) { SignInSheet() }
    }

    @ViewBuilder private var page: some View {
        switch step {
        case .hello: hello
        case .level: levelPage
        case .engines: enginesPage
        case .account: accountPage
        }
    }

    private var hello: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            ChessMark().frame(width: 64, height: 64).padding(.bottom, 30)
            Text("Zeist Chess").font(Z.title(48, relativeTo: .largeTitle)).padding(.bottom, 14)
            Text("Chess against the engines you choose, from Stockfish to engines that play like people. They run on this iPhone, with or without a connection.")
                .font(Z.text(17)).foregroundStyle(Z.soft).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The page as it is when it fits, and scrolling when it does not (the largest text sizes).
    private var levelPage: some View {
        ViewThatFits(in: .vertical) {
            levelBody
            ScrollView { levelBody }.scrollIndicators(.hidden)
        }
    }

    private var levelBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: tight ? 4 : 20)
            Text("How well do you play?").font(Z.title(34, relativeTo: .largeTitle))
                .lineLimit(tight && typeSize <= .large ? 1 : nil).minimumScaleFactor(tight && typeSize <= .large ? 0.8 : 1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
            Text("Games start there and move with your results, quickly at first. Skip this and they start at the easiest level.")
                .font(Z.text(15.5)).foregroundStyle(Z.soft).fixedSize(horizontal: false, vertical: true).padding(.bottom, tight ? 16 : 24)
            VStack(spacing: tight ? 8 : 10) {
                ForEach(Self.answers, id: \.2) { a in
                    Button {
                        level = a.2
                        Feel.shared.select()
                    } label: {
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(a.0).font(Z.medium(16.5))
                                Text(a.1).font(Z.text(14)).opacity(0.7).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                        }
                        .foregroundStyle(level == a.2 ? Z.ground : Z.ink)
                        .padding(.horizontal, 18).padding(.vertical, tight ? 11 : 14)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(level == a.2 ? Z.ink : .clear))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(level == a.2 ? .clear : Z.hair, lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(Press())
                    .accessibilityAddTraits(level == a.2 ? .isSelected : [])
                    .accessibilityIdentifier("level-\(a.2)")
                }
            }
            .animation(.easeOut(duration: 0.15), value: level)
            Spacer(minLength: tight ? 8 : 20)
        }
    }

    private var enginesPage: some View {
        let built = shelf.engines.filter(\.bundled)
        let more = shelf.engines.filter { !$0.bundled && !$0.installed }
        let count = built.count == 1 ? "One engine comes" : "\((NumberFormatter.localizedString(from: built.count as NSNumber, number: .spellOut)).capitalized) engines come"
        return VStack(alignment: .leading, spacing: 0) {
            Text("Engines").font(Z.title(34, relativeTo: .largeTitle)).padding(.top, tight ? 4 : 20).padding(.bottom, 10)
            Text("\(count) with the app. Choose any others to download now, or later in Settings, behind the button at the top right.")
                .font(Z.text(15.5)).foregroundStyle(Z.soft).fixedSize(horizontal: false, vertical: true).padding(.bottom, 16)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(built) { e in
                        if e.id != built.first?.id { Rectangle().fill(Z.hair).frame(height: 1) }
                        pickRow(e, on: true, fixed: true)
                    }
                    ForEach(more) { e in
                        Rectangle().fill(Z.hair).frame(height: 1)
                        pickRow(e, on: chosen.contains(e.id), fixed: false)
                    }
                }
            }
            .scrollIndicators(.hidden)
            if !chosen.isEmpty {
                Text("\(chosen.count == 1 ? "1 engine" : "\(chosen.count) engines"), \(Bytes.say(chosen.compactMap { shelf.engine($0)?.manifest.downloadBytes }.reduce(0, +))) in all.")
                    .font(Z.text(13.5)).foregroundStyle(Z.dim).padding(.top, 10).monospacedDigit()
            }
        }
    }

    private func pickRow(_ e: Engine, on: Bool, fixed: Bool) -> some View {
        Button {
            guard !fixed else { return }
            if chosen.contains(e.id) { chosen.remove(e.id) } else { chosen.insert(e.id) }
            Feel.shared.select()
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(e.name).font(Z.title(18, relativeTo: .headline)).lineLimit(1)
                    if let l = e.manifest.line { Text(l).font(Z.text(13.5)).foregroundStyle(Z.soft).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 8)
                Text(fixed ? "Built in" : Bytes.say(e.manifest.downloadBytes)).font(Z.text(13)).foregroundStyle(Z.dim).monospacedDigit()
                ZStack {
                    Circle().strokeBorder(on ? Color.clear : Z.ink.opacity(0.3), lineWidth: 1.5)
                    if on { Circle().fill(fixed ? Z.ink.opacity(0.35) : Z.ink); Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Z.ground) }
                }
                .frame(width: 24, height: 24)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("choose-\(e.id)")
    }

    private var accountPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Text(account.signedIn ? "Signed in" : "Your Zeist account").font(Z.title(34, relativeTo: .largeTitle)).padding(.bottom, 12)
            if account.signedIn {
                HStack(spacing: 12) {
                    Avatar(me: account.me, size: 44)
                    Text(account.handle.map { "@\($0)" } ?? "Signed in").font(Z.medium(17))
                }
            } else {
                Text("Sign in to Zeist to keep your games under your account. Everything plays without it.")
                    .font(Z.text(16.5)).foregroundStyle(Z.soft).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                if step == .account && !account.signedIn {
                    Button("Not now") { finish() }.buttonStyle(Pill(wide: true)).accessibilityIdentifier("not-now")
                    Button("Sign in") { Feel.shared.select(); signingIn = true }.buttonStyle(Pill(solid: true, wide: true))
                } else {
                    if step != .hello {
                        Button { go(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(Pill()).accessibilityLabel("Back")
                    }
                    Button(nextLabel) { next() }.buttonStyle(Pill(solid: true, wide: true)).accessibilityIdentifier("next")
                }
            }
            HStack(spacing: 7) {
                ForEach(Step.allCases, id: \.self) { s in
                    Capsule().fill(s == step ? Z.ink : Z.ink.opacity(0.2)).frame(width: s == step ? 18 : 6, height: 6)
                }
            }
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.35), value: step)
            .accessibilityHidden(true)
            // Said once, on the last page; its room is kept on every page so the buttons don't move, except on a
            // short screen, where the other pages need that room.
            if !tight || step == .account {
            Text("Your games against Zeist help it play better.\nOnly the moves are sent, with nothing about you.")
                .font(Z.text(12.5)).foregroundStyle(Z.dim).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.top, -4)
                .opacity(step == .account && EngineGames.on ? 1 : 0)
                .accessibilityHidden(!(step == .account && EngineGames.on))
                .accessibilityIdentifier("sharing-note")
            }
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 24).padding(.bottom, 14)
    }

    private var nextLabel: String {
        switch step {
        case .hello: "Begin"
        case .level: "Next"
        case .engines: chosen.isEmpty ? "Next" : "Download and go on"
        case .account: "Start playing"
        }
    }

    private func next() {
        Feel.shared.select()
        switch step {
        case .level:
            if let level { UserDefaults.standard.set(level, forKey: GameModel.startKey) }
        case .engines:
            for id in chosen { shelf.download(id) }
        case .account:
            finish(); return
        case .hello: break
        }
        go(1)
    }

    private func go(_ d: Int) {
        guard let s = Step(rawValue: step.rawValue + d) else { return }
        forward = d > 0
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .timingCurve(0.23, 1, 0.32, 1, duration: 0.42)) { step = s }
    }

    private func finish() {
        if let level, UserDefaults.standard.object(forKey: GameModel.startKey) == nil { UserDefaults.standard.set(level, forKey: GameModel.startKey) }
        done()
    }
}
