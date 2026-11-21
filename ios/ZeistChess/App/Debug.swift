#if DEBUG
import SwiftUI

/// Launch arguments for screenshots and UI tests. Debug builds only.
///   -reset              start with no games, no downloads, no settings
///   -packs <url>        read engines from this base URL instead of the configured one
///   -onboarding         with -reset: show onboarding
///   -onboarding-last    with -onboarding: begin on its last page
///   -onboarding-step <n> with -onboarding: begin on page n (counted from 0)
///   -theme <id>         a board theme
///   -pieces <id>        a piece set
///   -screen <name>      open start (the picker), game, puzzles, themes, today, learn, games or settings
///   -puzzle-theme <id>  open that puzzle theme (over Puzzles)
///   -today <yyyy-mm-dd> the daily puzzle's today, in place of the device's date
///   -daily-start <yyyy-mm-dd | none>  the daily's first day, in place of daily.json's (none: no daily)
///   -daily-solved <d,..> daily days already solved: "0,1,3@5" (day 3 solved on day 5; plain d is on its own day)
///   -lessons <folder>   read Learn's lessons from this folder instead of the app's (UI tests' fixtures)
///   -lesson <id>        open this lesson (over Learn)
///   -course <id>        open this course (over Learn)
///   -lesson-step <n>    with -lesson: open it at step n (counted from 0), or "last"
///   -puzzle <id>        with -screen puzzles: begin with this puzzle
///   -puzzle-answers     on the puzzle screen, the move the line expects, as an element for UI tests
///   -moves <uci,...>    with -screen game: a game with these moves already played (both sides)
///   -learn              with -screen game: a game started from Learn (Learn as you play's cards)
///   -time <pgn>         with -screen game: a timed game ("180+2")
///   -clock <w>,<b>      with -time: seconds left on White's and Black's clocks
///   -edge               the edge-to-edge board
///   -step <n>           with -screen game: look back at the position after n moves
///   -player b           with -screen game: play Black
///   -fen <fen>          with -screen game: start from this position
///   -freeze             the engine never answers (it stays "thinking")
///   -premove <uci>      with -freeze: a premove already entered
///   -engine-name <s>    show the engine under this name (worst cases)
///   -zeist-site <url>   Zeist is at this address for this run (a test server); with -zeist-token <token>, signed in there
///   -human              human mode on (a beaten engine may ask for a draw or resign)
///   -review-now         forget the rating request's record; the next good moment asks
///   -standard-captures  count captures from the usual start even in a game from a position
///   -rated-stub <games>,<rating>  signed in to a stand-in for Zeist that plays rated games here and never reaches
///                       it: the account has played <games> rated games, at <rating> once ranked (0: not ranked)
@MainActor
enum Debug {
    static var args: [String] { ProcessInfo.processInfo.arguments }
    static func value(_ key: String) -> String? {
        guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func prepare() {
        if args.contains("-reset") {
            for name in ["games", "engines", "catalog.json"] { try? FileManager.default.removeItem(at: Places.support.appending(path: name)) }
            if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
            Keychain.token = nil
            GameLog.shared.load()
            UserDefaults.standard.set(!args.contains("-onboarding"), forKey: "onboarded")
        }
        // With -zeist-site (Hosts.swift): a session of that test server's, in place of signing in through its pages.
        if args.contains("-zeist-site"), let t = value("-zeist-token") { Keychain.token = t }
        if let v = value("-rated-stub") { RatedStub.install(v) }
        if args.contains("-human") { UserDefaults.standard.set(true, forKey: GameModel.humanKey) }
        if args.contains("-review-now") { ReviewRequest.shared.forceNext() }
        if let t = value("-theme") { UserDefaults.standard.set(t, forKey: Look.key) }
        if let p = value("-pieces") { UserDefaults.standard.set(p, forKey: Look.piecesKey) }
        if let p = value("-packs") { UserDefaults.standard.set(p, forKey: "packsURL") }
        if args.contains("-edge") { UserDefaults.standard.set(true, forKey: Look.edgeKey) }
        if let list = value("-daily-solved") {
            var p = PuzzleProgress.load()
            for item in list.split(separator: ",") {
                let parts = item.split(separator: "@").compactMap { Int($0) }
                guard let d = parts.first else { continue }
                p.solveDaily(day: d, id: "debug-\(d)", missed: false, on: parts.count > 1 ? parts[1] : d)
            }
            p.save()
        }
    }

    static func run(path: Binding<[Route]>) {
        if value("-screen") == "rating" { path.wrappedValue = [.settings]; return }
        if let id = value("-lesson") {
            Session.shared.tab = .learn
            path.wrappedValue = [.lesson(id)]
            return
        }
        if let id = value("-course") {
            Session.shared.tab = .learn
            path.wrappedValue = [.course(id)]
            return
        }
        if let id = value("-puzzle-theme") {
            Session.shared.tab = .puzzles
            path.wrappedValue = [.themes, .theme(id)]
            return
        }
        guard let screen = value("-screen") else { return }
        Task {
            switch screen {
            case "start":
                try? await Task.sleep(for: .seconds(0.6))
                Session.shared.openPicker = true
            case "game":
                guard let e = Shelf.shared.engine(Shelf.bundledID) else { return }
                let moves = value("-moves")?.split(separator: ",").map(String.init) ?? []
                let time = value("-time").flatMap(TimeControl.init(pgn:))
                guard let m = try? await GameModel.begin(engine: e, player: value("-player") ?? "w", level: 3, adaptive: true, time: time,
                                                         start: value("-fen") ?? GameModel.standardStart, learn: args.contains("-learn")) else { return }
                if !moves.isEmpty { await m.load(moves) }
                if let c = value("-clock")?.split(separator: ",").compactMap({ Double($0) }), c.count == 2 { m.setClock(white: c[0], black: c[1]) }
                Session.shared.game = m
                path.wrappedValue = [.game]
                if let p = value("-premove") {
                    try? await Task.sleep(for: .seconds(1.5))
                    m.setPremove(p)
                }
                if let n = value("-step").flatMap(Int.init) {
                    try? await Task.sleep(for: .seconds(1.5))
                    m.step(to: n)
                }
                if let s = value("-select").flatMap({ Square.index($0) }) {
                    try? await Task.sleep(for: .seconds(1.5))
                    m.selected = s
                }
            case "puzzles": Session.shared.tab = .puzzles
            case "themes": Session.shared.tab = .puzzles; path.wrappedValue = [.themes]
            case "today":
                Session.shared.tab = .puzzles
                if let d = DailyCalendar.today(of: PuzzleSet.shared.daily) {
                    path.wrappedValue = [.today(d)]
                }
            case "learn": Session.shared.tab = .learn
            case "games": path.wrappedValue = [.games]
            case "settings": path.wrappedValue = [.settings]
            default: break
            }
        }
    }
}
/// A stand-in for Zeist's account and rated games, for screenshots and trying the screens. Each finish is a win
/// worth +14 (after ten games), and Matched picks level 3.
@MainActor
enum RatedStub {
    static var games = 0, rating = 0

    static func install(_ v: String) {
        let p = v.split(separator: ",").compactMap { Int($0) }
        games = p.first ?? 0
        rating = p.count > 1 ? p[1] : 0
        Keychain.token = "stub"
        Account.shared.fetch = { req in
            (Data(#"{"user":{"handle":"tester","display_name":"Tester","owner":"stub-owner","chess_archive":false}}"#.utf8),
             HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        Rated.net = { req in
            let path = req.url!.path
            let body = req.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            if req.httpMethod == "GET" { return (standing(), 200) }
            if path == "/api/rated" {
                let level = body["level"] as? Int ?? 3
                let seat = body["seat"] as? Int ?? 0
                return (Data(#"{"ok":true,"id":"stub\#(Int.random(in: 100000...999999))0000000000","level":{"level":\#(level)},"seed":\#(UInt32.random(in: 1...UInt32.max)),"seat":\#(seat)}"#.utf8), 200)
            }
            if path.hasPrefix("/api/rated/") {
                games += 1
                if games >= Rated.untilRanked { rating = rating == 0 ? 1482 : rating + 14 }
                return (Data(#"{"ok":true,"outcome":"win"}"#.utf8), 200)
            }
            return (Data(), 404)
        }
    }

    static func standing() -> Data {
        let ranked = games >= Rated.untilRanked && rating > 0
        let r = ranked ? #""rating":\#(rating),"record":{"won":\#(games / 2),"drawn":\#(games / 10),"lost":\#(games - games / 2 - games / 10)},"# : ""
        return Data(#"{"ok":true,\#(r)"games":\#(games),"rank_level":\#(ranked ? 3 : 0),"rank_name":"\#(ranked ? "Amateur" : "New")","until_ranked":\#(max(0, Rated.untilRanked - games)),"level":\#(ranked ? 3 : 2)}"#.utf8)
    }
}
#endif
