import SwiftUI

enum Route: Hashable {
    case game
    case settings
    case games
    case replay(UUID)
    /// Learn: a course, a chapter of it (an opening's own page), a lesson.
    case course(String)
    case chapter(String, String)
    case lesson(String)
    /// Puzzles: the themes, one theme's puzzles, and a day's daily puzzle (by day number).
    case themes
    case theme(String)
    case today(Int)
}

/// The game being played, handed from Home to the game screen.
@MainActor @Observable
final class Session {
    static let shared = Session()
    var game: GameModel?
    /// Opens Home's picker (screenshots and tests).
    var openPicker = false
    /// The place shown in the dock.
    var tab: Place = .play
    enum Place: Hashable { case play, puzzles, learn, games }
    /// Set by the profile button at the top right of each place: Root then opens Settings over the dock.
    var openSettings = false
}

@main
struct ZeistChessApp: App {
    init() {
        let bar = UINavigationBar.appearance()
        if let big = UIFont(name: "Prata-Regular", size: 34), let small = UIFont(name: "Prata-Regular", size: 19) {
            bar.largeTitleTextAttributes = [.font: big, .foregroundColor: UIColor(Z.ink)]
            bar.titleTextAttributes = [.font: small, .foregroundColor: UIColor(Z.ink)]
        }
        #if DEBUG
        Debug.prepare()
        #endif
        Measure.start()
        GameCenter.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            Root()
                .preferredColorScheme(.dark)
                .tint(Z.ink)
        }
    }
}

struct Root: View {
    @State private var path: [Route] = []
    @State private var session = Session.shared
    @AppStorage("onboarded") private var onboarded = false
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationStack(path: $path) {
            // The places sit in the system's tab bar, Liquid Glass on iOS 26, as in the main Zeist app.
            // A game, a replay and anything else pushed covers the bar.
            TabView(selection: $session.tab) {
                Tab("Play", systemImage: "checkerboard.rectangle", value: Session.Place.play) { Home(path: $path) }
                Tab("Puzzles", systemImage: "puzzlepiece", value: Session.Place.puzzles) { PuzzleScreen(path: $path) }
                Tab("Learn", systemImage: "book", value: Session.Place.learn) { LearnScreen(path: $path) }
                Tab("Games", systemImage: "clock.arrow.circlepath", value: Session.Place.games) { GamesScreen(path: $path, tab: true) }
            }
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .game:
                        if let m = Session.shared.game { GameScreen(model: m, path: $path) } else { Home(path: $path) }
                    case .settings: SettingsScreen()
                    case .games: GamesScreen(path: $path)
                    case .replay(let id): ReplayScreen(id: id)
                    case .course(let id): CourseScreen(id: id, path: $path)
                    case .chapter(let course, let id): ChapterScreen(course: course, id: id, path: $path)
                    case .lesson(let id): LessonScreen(id: id, path: $path)
                    case .themes: ThemesScreen(path: $path)
                    case .theme(let id): ThemePuzzleScreen(id: id, path: $path)
                    case .today(let day): TodayScreen(day: day, path: $path)
                    }
                }
        }
        .background(Z.ground.ignoresSafeArea())
        .fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { if !$0 { onboarded = true } })) {
            Onboarding { onboarded = true }
        }
        .task {
            Core.shared.boot()
            ReviewRequest.shared.record(.opened)
            await Account.shared.refresh()
            await EngineGames.flush()
            #if DEBUG
            Debug.run(path: $path)
            #endif
        }
        .onChange(of: session.openSettings) { _, open in
            guard open else { return }
            session.openSettings = false
            if path.last != .settings { path.append(.settings) }
        }
        .onChange(of: phase) { _, p in
            ReviewRequest.shared.movedOn()
            guard p == .active else { return }
            ReviewRequest.shared.record(.opened)
            Task { await Account.shared.refresh() }
        }
        .onChange(of: path) { _, _ in ReviewRequest.shared.movedOn() }
        .onChange(of: session.tab) { _, _ in ReviewRequest.shared.movedOn() }
        // zeistchess:// opens the app on Play; zeistchess://engine/<id> also picks that engine if it is on this iPhone
        // (otherwise it opens the picker, where it can be downloaded).
        .onOpenURL { url in
            guard url.scheme == "zeistchess" else { return }
            path = []
            session.tab = .play
            guard url.host == "engine", let id = url.pathComponents.dropFirst().first,
                  id.range(of: "^[a-z0-9-]{1,40}$", options: .regularExpression) != nil else { return }
            if Shelf.shared.engine(id)?.installed == true { UserDefaults.standard.set(id, forKey: Pick.engineKey) }
            else { session.openPicker = true }
        }
    }
}
