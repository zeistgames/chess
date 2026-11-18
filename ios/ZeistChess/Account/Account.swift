import AuthenticationServices
import Foundation
import Observation
import Security
import UIKit

/// Signing in to Zeist. The sign-in runs on Zeist's site (Hosts.primary) in the system's secure sign-in window, which hands back a
/// one-time code through the zeist:// scheme; the code is swapped for a session token, kept in the Keychain.
/// Nothing is uploaded in this version: signed in, games in the log carry the account's owner tag.
@MainActor @Observable
final class Account: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = Account()
    static let base = Hosts.site

    struct Me: Codable, Equatable, Sendable {
        var handle: String?
        var display_name: String?
        var picture: String?
        var owner: String?
        var needs_handle: Bool?
        /// The account's choice on Zeist, "Help improve the chess computer". Nil when Zeist's answer didn't carry a
        /// plain yes or no: then the choice isn't known, and games wait (see EngineGames).
        var chess_archive: Bool?

        init(handle: String? = nil, display_name: String? = nil, picture: String? = nil, owner: String? = nil,
             needs_handle: Bool? = nil, chess_archive: Bool? = nil) {
            self.handle = handle; self.display_name = display_name; self.picture = picture; self.owner = owner
            self.needs_handle = needs_handle; self.chess_archive = chess_archive
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            handle = try c.decodeIfPresent(String.self, forKey: .handle)
            display_name = try c.decodeIfPresent(String.self, forKey: .display_name)
            picture = try c.decodeIfPresent(String.self, forKey: .picture)
            owner = try c.decodeIfPresent(String.self, forKey: .owner)
            needs_handle = try c.decodeIfPresent(Bool.self, forKey: .needs_handle)
            chess_archive = try? c.decode(Bool.self, forKey: .chess_archive)   // anything but true or false: not known
        }
    }

    private(set) var me: Me?
    /// The network, replaceable in tests.
    var fetch: @MainActor (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }
    private(set) var busy = false
    var problem: String?

    var signedIn: Bool { me != nil }
    var handle: String? { me?.handle }
    var owner: String? { me?.owner }
    /// A session is held, whether or not Zeist has been heard from yet.
    var hasSession: Bool { Keychain.token != nil }

    private override init() {
        super.init()
        if Keychain.token != nil, let data = UserDefaults.standard.data(forKey: "account.me") {
            me = try? JSONDecoder().decode(Me.self, from: data)
        }
    }

    /// Checks the token with Zeist. A token it no longer knows signs you out; offline keeps what was known.
    /// Returns whether what is known now is fresh: Zeist answered for the session held, or there is no session.
    @discardableResult
    func refresh() async -> Bool {
        guard let token = Keychain.token else { me = nil; return true }
        var req = URLRequest(url: Self.base.appending(path: "/api/me"), timeoutInterval: 15)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await fetch(req),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
        struct Answer: Decodable { var user: Me? }
        guard let a = try? JSONDecoder().decode(Answer.self, from: data) else { return false }
        // An answer counts only for the session it was asked for: a newer sign-in (or sign-out) since then wins.
        guard Keychain.token == token else { return false }
        if let u = a.user { keep(u) } else { forget() }
        return true
    }

    /// Deletes the Zeist account itself (DELETE /api/me), everywhere, and signs this iPhone out. Games on this
    /// iPhone stay. Returns whether Zeist confirmed it; on anything else nothing here changes.
    func delete() async -> Bool {
        guard let token = Keychain.token else { return false }
        var req = URLRequest(url: Self.base.appending(path: "/api/me"), timeoutInterval: 20)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let was = owner
        struct Answer: Decodable { var ok: Bool? }
        var done = false
        if let (data, response) = try? await fetch(req), (response as? HTTPURLResponse)?.statusCode == 200 {
            done = (try? JSONDecoder().decode(Answer.self, from: data))?.ok == true
        }
        if !done {
            // The answer may have been lost on the way back: ask who this session is. If Zeist no longer knows it,
            // refresh has signed out and the account is gone.
            guard Keychain.token == token, await refresh(), Keychain.token == nil else { return false }
        }
        // Forget only the session whose account was deleted: a newer sign-in since then stays.
        if Keychain.token == token { forget() }
        if let was {
            GameLog.shared.release(owner: was)
            EngineGames.forget(owner: was)
        }
        return true
    }

    private func keep(_ u: Me) {
        me = u
        UserDefaults.standard.set(try? JSONEncoder().encode(u), forKey: "account.me")
        if let owner = u.owner { GameLog.shared.stamp(owner: owner, handle: u.handle) }
    }

    private func forget() {
        Keychain.token = nil
        me = nil
        UserDefaults.standard.removeObject(forKey: "account.me")
    }

    /// provider: "apple" or "google".
    func signIn(_ provider: String) async {
        problem = nil
        busy = true
        defer { busy = false }
        var c = URLComponents(url: Self.base.appending(path: "/auth/\(provider)"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "return", value: "/app")]
        do {
            let back = try await webSignIn(c.url!)
            let items = URLComponents(url: back, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if items.contains(where: { $0.name == "error" }) { throw PackError("refused") }
            guard let code = items.first(where: { $0.name == "code" })?.value else { throw PackError("no code") }
            var req = URLRequest(url: Self.base.appending(path: "/auth/app/exchange"), timeoutInterval: 20)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["code": code])
            let (data, _) = try await URLSession.shared.data(for: req)
            struct Exchange: Decodable { var ok: Bool; var token: String? }
            guard let x = try? JSONDecoder().decode(Exchange.self, from: data), x.ok, let token = x.token else { throw PackError("exchange") }
            Keychain.token = token
            await refresh()
            if me == nil { throw PackError("me") }
            Feel.shared.select()
        } catch let e as ASWebAuthenticationSessionError where e.code == .canceledLogin {
            return
        } catch {
            problem = "That sign-in didn't go through. Try again."
        }
    }

    func signOut() async {
        if let token = Keychain.token {
            var req = URLRequest(url: Self.base.appending(path: "/auth/signout"), timeoutInterval: 10)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await fetch(req)
            // Forget only the session that asked to sign out: a newer sign-in since then stays.
            guard Keychain.token == token else { return }
        }
        forget()
    }

    private func webSignIn(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { c in
            let s = ASWebAuthenticationSession(url: url, callback: .customScheme("zeist")) { back, error in
                if let back { c.resume(returning: back) } else { c.resume(throwing: error ?? PackError("none")) }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = true
            s.start()
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}

/// The session token, in the Keychain, on this device only.
enum Keychain {
    private static let service = "st.zei.Chess.session"

    static var token: String? {
        get {
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
            var out: AnyObject?
            guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
            return String(data: d, encoding: .utf8)
        }
        set {
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
            SecItemDelete(q as CFDictionary)
            guard let newValue else { return }
            var add = q
            add[kSecValueData as String] = Data(newValue.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
