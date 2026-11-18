import Foundation

/// Where Zeist is served, in one place for the app.
/// `primary` is the site: pages, profiles, sign-in and the API. `short` is for short links.
/// Engine files (Config.xcconfig) and the bundle id are not part of this and do not change with it.
enum Hosts {
    static let primary = "zeist.gg"
    static let short = "zei.st"

    static let site = URL(string: "https://\(primary)")!
    /// A page or an API path on the site: Hosts.page("privacy") is https://<primary>/privacy.
    static func page(_ path: String) -> URL { site.appending(path: path) }
}
