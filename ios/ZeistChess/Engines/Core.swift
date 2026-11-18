import Foundation
import UIKit
import WebKit

/// Serves the web view its files: zchess://app/core/... from the app, and zchess://app/engines/<id>/...: program files
/// (PackFiles) only ever from the app, data files from Application Support (downloaded) or the app. Nothing else.
final class SchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "zchess"

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let file = Self.file(for: url) else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        do {
            let data = try Data(contentsOf: file, options: .mappedIfSafe)
            let headers = ["Content-Type": Self.mime(file.pathExtension), "Content-Length": "\(data.count)", "Cache-Control": "no-store"]
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
            task.didReceive(response)
            task.didReceive(data)
            task.didFinish()
        } catch {
            task.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    static func file(for url: URL) -> URL? {
        guard url.scheme == scheme, url.host() == "app" else { return nil }
        let parts = url.path().split(separator: "/").map(String.init).compactMap { $0.removingPercentEncoding }
        guard !parts.contains(".."), let first = parts.first else { return nil }
        let rest = parts.dropFirst().joined(separator: "/")
        switch first {
        case "core":
            return existing(Places.core.appending(path: rest))
        case "engines":
            guard parts.count >= 3 else { return nil }
            let id = parts[1], inner = parts.dropFirst(2).joined(separator: "/")
            let bundled = existing(Places.bundledEngines.appending(path: "\(id)/\(inner)"))
            guard PackFiles.isData(inner) else { return bundled }
            return existing(Places.engines.appending(path: "\(id)/\(inner)")) ?? bundled
        default:
            return nil
        }
    }

    private static func existing(_ u: URL) -> URL? { FileManager.default.fileExists(atPath: u.path) ? u : nil }

    static func mime(_ ext: String) -> String {
        switch ext.lowercased() {
        case "html": "text/html; charset=utf-8"
        case "js", "mjs": "text/javascript; charset=utf-8"
        case "json": "application/json"
        case "wasm": "application/wasm"
        case "txt": "text/plain; charset=utf-8"
        default: "application/octet-stream"
        }
    }
}

enum CoreError: Error, Equatable {
    /// The web view went away (memory pressure) while this call was out. Ask again.
    case restarted
    /// A search that was ended or replaced.
    case stale
    /// A timed search reached the engine's flag with nothing to play.
    case outOfTime
    case failed(String)
}

/// The hidden web view that runs core/: the rules and the engines. Calls are async and carry the whole game,
/// so if iOS ends the web view's process the next call simply starts it again.
@MainActor
final class Core: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let shared = Core()

    private var web: WKWebView?
    private var ready = false
    private var waitingForReady: [CheckedContinuation<Void, Error>] = []
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var nextID = 1
    /// How many times the web view has been made (more than one means it recovered at least once).
    private(set) var generation = 0
    /// Told when the web view had to be remade, so a game can ask for its move again.
    var onRestart: (() -> Void)?

    func boot() { if web == nil { make() } }

    private func make() {
        generation += 1
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(SchemeHandler(), forURLScheme: SchemeHandler.scheme)
        cfg.websiteDataStore = .nonPersistent()
        cfg.userContentController.add(WeakHandler(self), name: "zeist")
        cfg.suppressesIncrementalRendering = true
        let w = WKWebView(frame: CGRect(x: 0, y: 0, width: 2, height: 2), configuration: cfg)
        w.navigationDelegate = self
        w.isUserInteractionEnabled = false
        w.alpha = 0.01
        #if DEBUG
        if #available(iOS 16.4, *) { w.isInspectable = true }
        #endif
        web = w
        ready = false
        attach(w)
        // No network from the page: engines and rules only ever load from the app.
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "zchess-offline", encodedContentRuleList: Self.offline) { list, _ in
            Task { @MainActor in
                if let list { w.configuration.userContentController.add(list) }
                w.load(URLRequest(url: URL(string: "zchess://app/core/index.html")!))
            }
        }
    }

    /// Blocks every web address. WebKit's url-filter has no alternation ("a|b" fails to compile, and then nothing is
    /// blocked), so one rule each.
    static let offline = #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}},{"trigger":{"url-filter":"^wss?://"},"action":{"type":"block"}}]"#

    /// The web view sits in the window, almost invisible, so iOS keeps its timers running.
    private func attach(_ w: WKWebView) {
        if let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first {
            window.insertSubview(w, at: 0)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self, weak w] in
                guard let self, let w, w.superview == nil, self.web === w else { return }
                self.attach(w)
            }
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        recover(webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { recover(webView) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { recover(webView) }

    private func recover(_ webView: WKWebView) {
        guard webView === web else { return }
        webView.removeFromSuperview()
        web = nil
        ready = false
        let calls = pending
        pending = [:]
        for (_, c) in calls { c.resume(throwing: CoreError.restarted) }
        make()
        onRestart?()
    }

    #if DEBUG
    /// For tests: behave as if iOS ended the web view's process.
    func simulateCrash() { if let w = web { recover(w) } }
    #endif

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        receive(message.body)
    }

    private func receive(_ body: Any) {
        guard let m = body as? [String: Any], let id = m["id"] as? Int else { return }
        if id == 0 {
            ready = true
            let w = waitingForReady; waitingForReady = []
            for c in w { c.resume() }
            return
        }
        guard let c = pending.removeValue(forKey: id) else { return }
        if m["ok"] as? Bool == true {
            let data = (try? JSONSerialization.data(withJSONObject: m["value"] ?? NSNull(), options: [.fragmentsAllowed])) ?? Data("null".utf8)
            c.resume(returning: data)
        }
        else if m["stale"] as? Bool == true { c.resume(throwing: CoreError.stale) }
        else if m["outOfTime"] as? Bool == true { c.resume(throwing: CoreError.outOfTime) }
        else { c.resume(throwing: CoreError.failed(m["error"] as? String ?? "unknown")) }
    }

    private func whenReady() async throws {
        if web == nil { make() }
        if ready { return }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in waitingForReady.append(c) }
    }

    /// Calls a method in core/bridge.js. Retries once if the web view restarts during the call.
    func call(_ method: String, _ args: [String: Any] = [:]) async throws -> Any {
        let data = try await raw(method, args)
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    func raw(_ method: String, _ args: [String: Any] = [:]) async throws -> Data {
        do { return try await once(method, args) } catch CoreError.restarted {
            return try await once(method, args)
        }
    }

    private func once(_ method: String, _ args: [String: Any]) async throws -> Data {
        try await whenReady()
        guard let web else { throw CoreError.restarted }
        let id = nextID
        nextID += 1
        let json = String(data: try JSONSerialization.data(withJSONObject: args), encoding: .utf8)!
        return try await withCheckedThrowingContinuation { c in
            pending[id] = c
            web.evaluateJavaScript("window.zeist.call(\(id), \(Self.quote(method)), \(json)); 0") { [weak self] _, error in
                if let error, let self, let c = self.pending.removeValue(forKey: id) { c.resume(throwing: CoreError.failed(error.localizedDescription)) }
            }
        }
    }

    /// Calls a function exported by a module in core/ (path relative to core/index.html, as "./learn/cards.js"), with
    /// one argument object, and returns its result as JSON. Lets shared logic beside the bridge, such as Learn as you
    /// play's cards, run exactly as the web runs it. Retries once if the web view restarts during the call.
    func module(_ path: String, _ function: String, _ args: [String: Any]) async throws -> Data {
        do { return try await moduleOnce(path, function, args) } catch CoreError.restarted {
            return try await moduleOnce(path, function, args)
        }
    }

    private func moduleOnce(_ path: String, _ function: String, _ args: [String: Any]) async throws -> Data {
        try await whenReady()
        guard let web else { throw CoreError.restarted }
        let js = "const m = await import(path); return JSON.stringify(await m[fn](args));"
        let value: Any?
        do {
            value = try await web.callAsyncJavaScript(js, arguments: ["path": path, "fn": function, "args": args], contentWorld: .page)
        } catch {
            if self.web !== web { throw CoreError.restarted }
            throw CoreError.failed(error.localizedDescription)
        }
        guard let s = value as? String else { throw CoreError.failed("no answer from \(path)") }
        return Data(s.utf8)
    }

    func decode<T: Decodable>(_ type: T.Type, _ method: String, _ args: [String: Any] = [:]) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await raw(method, args))
    }

    private static func quote(_ s: String) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: s, options: .fragmentsAllowed), encoding: .utf8)!
    }
}

/// Keeps the content controller from holding Core strongly.
@MainActor
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?
    init(_ t: any WKScriptMessageHandler) { target = t }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(ucc, didReceive: message)
    }
}

extension Engine {
    /// What core/bridge.js needs to run this engine.
    var coreArgs: [String: Any] {
        let data = (try? JSONEncoder().encode(manifest)) ?? Data()
        let m = (try? JSONSerialization.jsonObject(with: data)) ?? [:]
        return ["base": base, "manifest": m]
    }
}
