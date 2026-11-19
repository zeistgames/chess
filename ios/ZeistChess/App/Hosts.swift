import Foundation

/// Where Zeist is served, in one place for the app.
/// `primary` is the site: pages, profiles, sign-in and the API. `short` is for short links.
/// Engine files (Config.xcconfig) and the bundle id are not part of this and do not change with it.
enum Hosts {
    static let primary = "zeist.gg"
    static let short = "zei.st"

    static let site: URL = {
        #if DEBUG
        // Debug builds only, for testing against a Zeist server that is not the real one: -zeist-site https://host.
        // The address must be one the system will load (https; the app carries no exception for plain http).
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-zeist-site"), i + 1 < args.count, let u = URL(string: args[i + 1]), u.scheme != nil, u.host != nil { return u }
        #endif
        return URL(string: "https://\(primary)")!
    }()
    /// Zeist Chess's source.
    static let repository = URL(string: "https://github.com/zeistgames/chess")!
    /// A page or an API path on the site: Hosts.page("privacy") is https://<primary>/privacy.
    static func page(_ path: String) -> URL { site.appending(path: path) }
}
