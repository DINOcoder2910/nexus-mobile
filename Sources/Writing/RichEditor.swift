import UIKit
import WebKit
import NexusCore

/// The laptop's rich-text block editor on the iPad (nexus docs/rich-text.md "Editors": the same editor in a web view): the page
/// Resources/RichText/rich.html (tools/richtext/editor.js, built from the laptop's code) edits a block's words as its doc with ProseMirror,
/// and hands them back as markdown on every change, the words the board keeps (content.texts) as on the laptop. The WritingSession that
/// owns it keeps everything else (the board's undo, drafts, comments, Review buttons, live words from the laptop) as with the plain editor;
/// places in the words cross the bridge as offsets in that markdown.
///
/// Settings › Notes › "Rich-text editor" switches it (on unless switched off); a block in Spanish practice uses the plain editor, which
/// turns the keyboard's checks off.
final class RichEditor: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let settingKey = "notes.richEditor"
    static var isOn: Bool { UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true }

    /// What the page last said about the caret: style, marks, the selection (markdown offsets), undo, counts, the caret's rectangle.
    struct State {
        var style: String = "body"
        var list: String?
        var marks: Set<String> = []
        var highlight: String?
        var color: String?
        var link: String?
        var canUndo = false
        var canRedo = false
        var selection = NSRange(location: 0, length: 0)
        var words = 0
        var chars = 0
        /// The caret in the page (points from the page's top left, not scrolled).
        var caret: CGRect?
    }

    weak var session: WritingSession?
    let web: RichWebView
    private(set) var loaded = false
    private var waiting: [String] = []
    private(set) var state = State()
    /// The words' height in the page (points at the session's styling scale).
    private(set) var contentHeight: CGFloat = 0
    /// Comment rectangles asked for, by request.
    private var asks: [Int: ([CGRect?]) -> Void] = [:]
    private var askId = 0

    // MARK: a few kept ready (a page takes a moment to load)

    private static var idle: [RichEditor] = []

    /// One editor ready before the first block is opened (a board calls this when it shows).
    static func prewarm() {
        guard isOn, idle.isEmpty else { return }
        idle.append(RichEditor())
    }

    static func take(for session: WritingSession) -> RichEditor {
        let e = idle.popLast() ?? RichEditor()
        e.session = session
        e.web.session = session
        return e
    }

    /// The session is over: the page is emptied and kept for the next block.
    func release() {
        call("rich.close()")
        web.resignFirstResponder()
        web.removeFromSuperview()
        web.transform = .identity
        web.accessory = nil
        session = nil
        web.session = nil
        state = State()
        contentHeight = 0
        if RichEditor.idle.count < 2 { RichEditor.idle.append(self) }
    }

    override init() {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        config.userContentController = controller
        config.dataDetectorTypes = []
        web = RichWebView(frame: CGRect(x: 0, y: 0, width: 300, height: 60), configuration: config)
        super.init()
        controller.add(WeakMessages(self), name: "rich")
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.bounces = false
        web.allowsLinkPreview = false
        web.navigationDelegate = self
        web.isInspectableIfAvailable()
        web.keepsAccessory()
        if let url = Bundle.main.url(forResource: "rich", withExtension: "html", subdirectory: "RichText") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    // MARK: talking to the page

    /// Runs `js` once the page is there (in order).
    func call(_ js: String) {
        if loaded { web.evaluateJavaScript(js, completionHandler: nil) } else { waiting.append(js) }
    }

    /// A value as a JavaScript literal (JSON).
    static func lit(_ v: Any?) -> String {
        guard let v, !(v is NSNull) else { return "null" }
        if let d = try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed]), let s = String(data: d, encoding: .utf8) {
            // (U+2028 and U+2029 are line ends to JavaScript inside a string literal in older engines)
            return s.replacingOccurrences(of: "\u{2028}", with: "\\u2028").replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        }
        return "null"
    }

    /// The block's words into the page. caret: "start" | "end" | "all", or a range (markdown offsets).
    func open(md: String, jsonl: String?, look: [String: Any], caret: Any, chem: Bool, review: Bool, locked: Bool, lang: String?, marked: [NSRange], focus: Bool = true) {
        let o: [String: Any] = [
            "md": md, "jsonl": jsonl ?? NSNull(), "look": look, "caret": caret, "chem": chem, "review": review, "locked": locked,
            "lang": lang ?? NSNull(), "marked": marked.map { [$0.location, NSMaxRange($0)] }, "focus": focus,
        ]
        call("rich.open(\(RichEditor.lit(o)))")
    }

    static func caret(_ r: NSRange) -> [String: Int] { ["loc": r.location, "len": r.length] }

    func setMd(_ md: String, selection: NSRange) { call("rich.setMd(\(RichEditor.lit(md)), \(selection.location), \(selection.length))") }
    func remote(_ md: String) { call("rich.remote(\(RichEditor.lit(md)))") }
    func select(_ r: NSRange) { call("rich.select(\(r.location), \(r.length))") }
    func cmd(_ name: String, _ arg: Any? = nil) { call("rich.cmd(\(RichEditor.lit(name)), \(RichEditor.lit(arg)))") }
    func setLook(_ look: [String: Any]) { call("rich.setLook(\(RichEditor.lit(look)))") }
    func setOpts(chem: Bool, review: Bool, locked: Bool) { call("rich.setOpts(\(RichEditor.lit(["chem": chem, "review": review, "locked": locked])))") }
    func setMarked(_ list: [NSRange]) { call("rich.setMarked(\(RichEditor.lit(list.map { [$0.location, NSMaxRange($0)] })))") }

    func focus() {
        RichWebView.focusing = true
        web.becomeFirstResponder()
        call("rich.focus()")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { RichWebView.focusing = false }
    }

    func blur() { call("rich.blur()"); web.resignFirstResponder() }

    /// The rectangles (page points, not scrolled) of markdown ranges: the Writing view's comment cards.
    func rects(_ list: [NSRange], _ done: @escaping ([CGRect?]) -> Void) {
        guard loaded else { done(list.map { _ in nil }); return }
        web.evaluateJavaScript("rich.rects(\(RichEditor.lit(list.map { [$0.location, NSMaxRange($0)] })))") { out, _ in
            let rows = (out as? [Any]) ?? []
            done(list.indices.map { i in
                guard i < rows.count, let r = rows[i] as? [String: Any], let x = r["x"] as? Double, let y = r["y"] as? Double else { return nil }
                return CGRect(x: x, y: y, width: r["w"] as? Double ?? 1, height: r["h"] as? Double ?? 16)
            })
        }
    }

    // MARK: what the page says

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}

    /// The page's process ended (memory pressure): load it again; the open block is put back by the session.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loaded = false
        webView.reload()
    }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let m = message.body as? [String: Any], let t = m["t"] as? String else { return }
        switch t {
        case "loaded":
            let first = !loaded
            loaded = true
            let w = waiting; waiting = []
            for js in w { web.evaluateJavaScript(js, completionHandler: nil) }
            if !first || w.isEmpty { session?.richReloaded() }
        case "change":
            if let md = m["md"] as? String { session?.richChanged(md) }
        case "state":
            var s = State()
            s.style = m["style"] as? String ?? "body"
            s.list = m["list"] as? String
            if let marks = m["marks"] as? [String: Any] { s.marks = Set(marks.compactMap { ($0.value as? Bool) == true ? $0.key : nil }) }
            s.highlight = m["hl"] as? String
            s.color = m["color"] as? String
            s.link = m["link"] as? String
            s.canUndo = m["canUndo"] as? Bool ?? false
            s.canRedo = m["canRedo"] as? Bool ?? false
            if let sel = m["sel"] as? [String: Any] { s.selection = NSRange(location: sel["loc"] as? Int ?? 0, length: sel["len"] as? Int ?? 0) }
            s.words = m["words"] as? Int ?? 0
            s.chars = m["chars"] as? Int ?? 0
            if let c = m["caret"] as? [String: Any], let x = c["x"] as? Double, let y = c["y"] as? Double {
                s.caret = CGRect(x: x, y: y, width: 2, height: c["h"] as? Double ?? 18)
            }
            state = s
            session?.richStateChanged()
        case "size":
            contentHeight = CGFloat(m["h"] as? Double ?? 0)
            session?.richSized()
        case "key":
            if let name = m["name"] as? String { session?.perform(name) }
        default: break
        }
    }

    // MARK: the block's look for the page

    /// BlockLook as the page's look: sizes at scale 1 (the page multiplies by `scale`), colours resolved for light or dark.
    static func look(_ look: BlockLook, scale: CGFloat, traits: UITraitCollection, box: TextBlockRender.Box?, page: UIEdgeInsets?) -> [String: Any] {
        func css(_ c: UIColor) -> String {
            let r = c.resolvedColor(with: traits)
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, a: CGFloat = 0
            r.getRed(&red, green: &green, blue: &blue, alpha: &a)
            let k = { (v: CGFloat) in Int((max(0, min(1, v)) * 255).rounded()) }
            return a >= 0.999 ? String(format: "#%02X%02X%02X", k(red), k(green), k(blue)) : "rgba(\(k(red)),\(k(green)),\(k(blue)),\(String(format: "%.3f", a)))"
        }
        func weight(_ w: UIFont.Weight) -> Int {
            let table: [(UIFont.Weight, Int)] = [(.ultraLight, 100), (.thin, 200), (.light, 300), (.regular, 400), (.medium, 500), (.semibold, 600), (.bold, 700), (.heavy, 800), (.black, 900)]
            return table.min { abs($0.0.rawValue - w.rawValue) < abs($1.0.rawValue - w.rawValue) }?.1 ?? 400
        }
        var styles: [String: Any] = [:]
        for s in BlockStyle.allCases {
            let st = look.style(s)
            styles[s.rawValue] = ["size": st.size, "weight": weight(st.weight), "color": css(st.color), "line": st.line, "before": st.before, "after": st.after, "indent": st.indent]
        }
        var out: [String: Any] = [
            "size": look.size, "scale": scale, "family": look.family, "color": css(look.color), "muted": css(BlockLook.muted), "accent": css(BlockLook.accent),
            "rule": css(BlockLook.rule), "codeBack": css(BlockLook.codeBack), "dark": traits.userInterfaceStyle == .dark, "styles": styles,
            "hl": Dictionary(uniqueKeysWithValues: BlockLook.highlights.map { ($0.key, css($0.color)) }),
            "colors": Dictionary(uniqueKeysWithValues: BlockLook.textColors.map { ($0.key, css($0.color)) }),
        ]
        if let box { out["padX"] = box.padX; out["padY"] = box.padY }
        if let page { out["fullscreen"] = true; out["page"] = ["top": page.top, "right": page.right, "bottom": page.bottom, "left": page.left] }
        return out
    }
}

/// The page's messages without the content controller keeping the editor alive.
private final class WeakMessages: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) { target?.userContentController(c, didReceive: m) }
}

/// The editor's web view: the board's format bar over the keyboard (as the plain editor's inputAccessoryView), the block keys
/// (BlockTextView's, the same list), and the edit menu's Comment, Read aloud, flashcard and task rows.
final class RichWebView: WKWebView {
    weak var session: WritingSession?
    /// The view over the keyboard while this page is being typed in.
    var accessory: UIView?

    /// True while the app focuses the page itself (a block just opened): the keyboard comes up although no finger is on the page.
    static var focusing = false

    override var keyCommands: [UIKeyCommand]? {
        BlockTextView.blockKeys(#selector(richKey(_:)))
    }

    @objc func richKey(_ sender: UIKeyCommand) {
        guard let action = sender.propertyList as? String else { return }
        session?.perform(action)
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .context, let s = session, let extra = s.menuRows(s.selectedRange) else { return }
        builder.insertSibling(UIMenu(options: .displayInline, children: extra), afterMenu: .standardEdit)
    }

    /// Lets the page say `isInspectable` where the system has it (Safari's Web Inspector on a Mac, for debugging a sideloaded build).
    func isInspectableIfAvailable() {
        if #available(iOS 16.4, *) { isInspectable = true }
    }

    // MARK: the bar over the keyboard

    /// WebKit's own text view (WKContentView) is what becomes first responder, so its inputAccessoryView is what shows over the keyboard:
    /// it is given a subclass of its own class that answers with this web view's `accessory`.
    func keepsAccessory() {
        guard let content = scrollView.subviews.first(where: { NSStringFromClass(type(of: $0)).hasPrefix("WKContent") }) else { return }
        let base: AnyClass = type(of: content)
        let name = NSStringFromClass(base) + "_NexusRich"
        if let cls = NSClassFromString(name) { object_setClass(content, cls); return }
        guard let cls = objc_allocateClassPair(base, name, 0) else { return }
        let accessory: @convention(block) (AnyObject) -> UIView? = { me in
            var v = me as? UIView
            while let x = v { if let w = x as? RichWebView { return w.accessory }; v = x.superview }
            return nil
        }
        class_addMethod(cls, #selector(getter: UIResponder.inputAccessoryView), imp_implementationWithBlock(accessory), "@@:")
        objc_registerClassPair(cls)
        object_setClass(content, cls)
        RichWebView.letFocusShowKeyboard(base)
    }

    /// A page focuses its words without a finger on it only with the keyboard staying down; while `focusing` (the app opening a block a
    /// tap asked for), WebKit is told the user is interacting, so the keyboard comes up. Left alone when WebKit has no such method.
    private static var swizzled = false
    static func letFocusShowKeyboard(_ content: AnyClass) {
        guard !swizzled else { return }
        swizzled = true
        let names = ["_elementDidFocus:userIsInteracting:blurPreviousNode:activityStateChanges:userObject:"]
        for n in names {
            let sel = NSSelectorFromString(n)
            guard let m = class_getInstanceMethod(content, sel) else { continue }
            typealias Fn = @convention(c) (AnyObject, Selector, UnsafeRawPointer?, Bool, Bool, UInt64, AnyObject?) -> Void
            let old = unsafeBitCast(method_getImplementation(m), to: Fn.self)
            let block: @convention(block) (AnyObject, UnsafeRawPointer?, Bool, Bool, UInt64, AnyObject?) -> Void = { me, info, user, blur, changes, obj in
                old(me, sel, info, user || RichWebView.focusing, blur, changes, obj)
            }
            method_setImplementation(m, imp_implementationWithBlock(block))
            return
        }
    }
}
