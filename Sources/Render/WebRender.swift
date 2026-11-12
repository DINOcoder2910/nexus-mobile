import UIKit
import WebKit

/// The laptop's own renderers on the iPad, offline: Resources/Render/render.html (built by tools/render/build.mjs from the laptop's code)
/// in one hidden web view. It holds KaTeX at the laptop's version (maths) and the study tools' chemistry diagrams (the tutor's chem steps).
/// Jobs run one at a time, because maths is laid out in the page's one box and then photographed.
@MainActor
final class WebRender: NSObject, WKNavigationDelegate {
    static let shared = WebRender()

    /// Starts WebKit's JavaScript engine in this process at launch. Its first start reserves a large block of memory addresses; left
    /// until the first tool, maths or tutor page minutes later, that reservation could fail and end the app (the Nov 12 crash on
    /// tapping Molecules in the Tools panel: JavaScriptCore pas_compact_heap_reservation_try_allocate under WKWebViewConfiguration.init).
    /// At launch the addresses are still free. The configuration is kept so the engine stays set up.
    private static var warm: WKWebViewConfiguration?
    nonisolated static func warmUp() {
        DispatchQueue.main.async { MainActor.assumeIsolated { if warm == nil { warm = WKWebViewConfiguration() } } }
    }

    private var web: WKWebView?
    private var loaded = false
    private var failed = false
    private var waiting: [CheckedContinuation<WKWebView?, Never>] = []
    private var tail: Task<Void, Never>?

    /// Runs `job` after every job asked for before it.
    func run<T: Sendable>(_ job: @escaping @MainActor (WKWebView) async -> T?) async -> T? {
        let before = tail
        let task = Task { @MainActor () -> T? in
            await before?.value
            guard let w = await view() else { return nil }
            return await job(w)
        }
        tail = Task { _ = await task.value }
        return await task.value
    }

    private func view() async -> WKWebView? {
        if failed { return nil }
        if let web, loaded { host(web); return web }
        if web == nil {
            guard let url = Bundle.main.url(forResource: "render", withExtension: "html", subdirectory: "Render") else { failed = true; return nil }
            let w = WKWebView(frame: CGRect(x: 0, y: 0, width: 1600, height: 1000), configuration: WKWebViewConfiguration())
            w.isOpaque = false
            w.backgroundColor = .clear
            w.scrollView.backgroundColor = .clear
            w.scrollView.isScrollEnabled = false
            w.isUserInteractionEnabled = false
            w.accessibilityElementsHidden = true
            w.navigationDelegate = self
            web = w
            host(w)
            w.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return await withCheckedContinuation { waiting.append($0) }
    }

    /// The web view only paints inside a window: it sits behind everything in the key window, covered by the app.
    private func host(_ w: WKWebView) {
        guard w.window == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let win = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first else { return }
        win.insertSubview(w, at: 0)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.loaded = true
            let w = self.waiting; self.waiting = []
            for c in w { c.resume(returning: webView) }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { Task { @MainActor in self.gaveUp() } }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { Task { @MainActor in self.gaveUp() } }

    /// The page's process can be ended by iOS when the app is in the background; it is loaded again on the next job.
    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor in self.loaded = false; webView.reload() }
    }

    private func gaveUp() {
        failed = true
        let w = waiting; waiting = []
        for c in w { c.resume(returning: nil) }
    }
}

/// Maths (KaTeX, as the laptop shows it) as an image, for typed blocks and the tutor. `cached` is synchronous for layout; `image` fills
/// the cache (call it, then lay out again when it returns). Sizes are in points, at the screen's scale; a formula KaTeX can't read gives nil
/// and `cannotRead` says so, so the block shows its TeX.
@MainActor
final class MathRender {
    static let shared = MathRender()

    private let cache = NSCache<NSString, UIImage>()
    private var bad: Set<String> = []
    private var asked: [String: Task<UIImage?, Never>] = [:]

    init() { cache.countLimit = 400 }

    func cached(tex: String, display: Bool, size: CGFloat, color: UIColor) -> UIImage? {
        cache.object(forKey: key(tex, display, size, color) as NSString)
    }

    func cannotRead(tex: String, display: Bool) -> Bool { bad.contains((display ? "D" : "I") + tex) }

    func image(tex: String, display: Bool, size: CGFloat, color: UIColor) async -> UIImage? {
        let k = key(tex, display, size, color)
        if let img = cache.object(forKey: k as NSString) { return img }
        if bad.contains((display ? "D" : "I") + tex) { return nil }
        if let t = asked[k] { return await t.value }
        let pt = MathRender.step(size), css = MathRender.css(color)
        let t = Task { @MainActor () -> UIImage? in
            await WebRender.shared.run { (web: WKWebView) -> UIImage? in
                guard let r = try? await web.callAsyncJavaScript("return await window.nexusMath(tex, display, size, color)",
                                                               arguments: ["tex": tex, "display": display, "size": Double(pt), "color": css],
                                                               in: nil, contentWorld: .page) as? [String: Any] else { return nil }
                guard (r["ok"] as? Bool) == true else { self.bad.insert((display ? "D" : "I") + tex); return nil }
                let w = (r["w"] as? Double) ?? 0, h = (r["h"] as? Double) ?? 0
                guard w > 0, h > 0 else { return nil }
                let cfg = WKSnapshotConfiguration()
                cfg.rect = CGRect(x: (r["x"] as? Double) ?? 0, y: (r["y"] as? Double) ?? 0, width: w, height: h)
                cfg.afterScreenUpdates = true
                return try? await web.takeSnapshot(configuration: cfg)
            }
        }
        asked[k] = t
        let img = await t.value
        asked[k] = nil
        if let img { cache.setObject(img, forKey: k as NSString) }
        return img
    }

    /// Sizes to the nearest half point, so zooming doesn't make a new picture at every step.
    static func step(_ size: CGFloat) -> CGFloat { max(4, (size * 2).rounded() / 2) }

    static func css(_ c: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return "rgba(\(Int((r * 255).rounded())),\(Int((g * 255).rounded())),\(Int((b * 255).rounded())),\(a))"
    }

    private func key(_ tex: String, _ display: Bool, _ size: CGFloat, _ color: UIColor) -> String {
        "\(display ? "D" : "I")|\(MathRender.step(size))|\(MathRender.css(color))|\(tex)"
    }
}

/// The tutor's chemistry diagrams drawn by the laptop's study tools (Lewis structure, VSEPR shape, Born–Haber cycle) as a PNG at 3x,
/// with its size in board units, or why there is none.
@MainActor
enum ChemRender {
    struct Picture: Sendable { let png: Data; let w: Double; let h: Double }

    static func picture(kind: String, molecule: String?, compound: String?, bp: Int?, lp: Int?) async -> Result<Picture, ChemError> {
        var step: [String: Any] = ["kind": kind]
        if let molecule { step["molecule"] = molecule }
        if let compound { step["compound"] = compound }
        if let bp { step["bp"] = bp }
        if let lp { step["lp"] = lp }
        let got: Result<Picture, ChemError>? = await WebRender.shared.run { (web: WKWebView) -> Result<Picture, ChemError>? in
            guard let r = try? await web.callAsyncJavaScript("return await window.nexusChem(step)", arguments: ["step": step], in: nil, contentWorld: .page) as? [String: Any]
            else { return .failure(ChemError(message: "the chemistry drawings didn't load")) }
            if let e = r["error"] as? String { return .failure(ChemError(message: e)) }
            guard let b64 = r["png"] as? String, let data = Data(base64Encoded: b64), let w = r["w"] as? Double, let h = r["h"] as? Double, w > 0, h > 0
            else { return .failure(ChemError(message: "no picture")) }
            return .success(Picture(png: data, w: w, h: h))
        }
        return got ?? .failure(ChemError(message: "the chemistry drawings didn't load"))
    }

    struct ChemError: Error, Sendable { let message: String }
}
