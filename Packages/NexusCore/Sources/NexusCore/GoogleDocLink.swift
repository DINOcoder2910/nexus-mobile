import Foundation

/// A typed block's Google Doc link, as the laptop keeps it (nexus docs/rich-text.md "Google Docs"; desktop/src/board/gdocs.tsx): the
/// `google` key of the block's `text/<id>.jsonl` header. Nexus writes `{doc}` to link a Doc or `{create, title}` to make one, and
/// `start` ("push" keeps the block's words, "pull" the Doc's) when both sides had words; the hub's bridge on the G14 does the rest and
/// writes back `{doc, url, title, tabs}` or an `error`. This file is the pure half: reading and writing that value, a Doc's id from
/// a pasted link, and what the panel says (the laptop's renderer/src/gdocs/gpanel.js `panelModel`, word for word).
public struct GoogleDocLink: Equatable {
    public var doc: String?
    public var start: String?
    public var create = false
    public var title: String?
    public var url: String?
    public var error: String?
    /// The value as it was read (tabs and anything newer the bridge wrote are kept from it).
    private var original: [(String, JSONValue)] = []

    public init(doc: String? = nil, start: String? = nil, create: Bool = false, title: String? = nil) {
        self.doc = doc; self.start = start; self.create = create; self.title = title
    }

    public static func == (a: GoogleDocLink, b: GoogleDocLink) -> Bool { a.json == b.json }

    /// The header's `google` value (nil: not linked, or not an object).
    public init?(_ v: JSONValue?) {
        guard let o = v?.object else { return nil }
        original = o
        for (k, x) in o {
            switch k {
            case "doc": doc = x.string
            case "start": start = x.string
            case "create": create = x.bool ?? false
            case "title": title = x.string
            case "url": url = x.string
            case "error": error = x.string
            default: break
            }
        }
    }

    /// As the header's value: the keys it was read with keep their places (what the bridge wrote stays as it wrote it).
    public var json: JSONValue {
        var o = JSONValue.object(original)
        o = o.setting("doc", doc.map(JSONValue.string))
        o = o.setting("start", start.map(JSONValue.string))
        o = o.setting("create", create ? .bool(true) : nil)
        o = o.setting("title", title.map(JSONValue.string))
        o = o.setting("url", url.map(JSONValue.string))
        o = o.setting("error", error.map(JSONValue.string))
        return o
    }

    /// The link with a side chosen (the error that asked for it taken off).
    public func choosing(_ side: String) -> GoogleDocLink {
        var g = self
        g.start = side
        g.error = nil
        return g
    }

    /// A Doc's id from what was pasted: its link (`…/document/d/<id>/edit`, `…/document/u/1/d/<id>`) or the bare id; nil otherwise.
    /// (The laptop's renderer/src/gdocs/gapi.js `docIdOf`.)
    public static func docId(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = t.range(of: #"/document/(?:u/\d+/)?d/([A-Za-z0-9_-]{10,})"#, options: .regularExpression) {
            let m = String(t[r])
            return m.components(separatedBy: "/d/").last.map { String($0.prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) }
        }
        return t.range(of: #"^[A-Za-z0-9_-]{10,}$"#, options: .regularExpression) != nil ? t : nil
    }

    /// A Doc's title from the block's words: its first line without the markdown marks (desktop/src/board/gdocs.tsx `titleFrom`).
    public static func title(from md: String) -> String {
        let first = md.split(separator: "\n", omittingEmptySubsequences: false).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        var s = String(first).replacingOccurrences(of: #"^\s*(#+|[-*+]|\d+[.)]|>)\s*"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[*_`~=\[\]{}$]"#, with: "", options: .regularExpression)
        return String(s.trimmingCharacters(in: .whitespaces).prefix(120))
    }
}

/// The hub's Google Docs as the panel needs it: `GET /v1/google/status`'s answer, or why there is none.
public struct GoogleHubState: Equatable, Sendable {
    /// "ok", "nohub" (sync with the hub isn't set up) or "error".
    public var state: String
    public var error: String?
    public var enabled: Bool?
    public var connected = false
    public var label: String?
    public var links: [GoogleLinkRound] = []

    public init(state: String, error: String? = nil, enabled: Bool? = nil, connected: Bool = false, label: String? = nil, links: [GoogleLinkRound] = []) {
        self.state = state; self.error = error; self.enabled = enabled; self.connected = connected; self.label = label; self.links = links
    }

    /// The hub's answer to `GET /v1/google/status`.
    public init(status v: JSONValue) {
        state = "ok"
        enabled = v["enabled"]?.bool
        connected = v["connected"]?.bool ?? false
        label = v["label"]?.string
        links = (v["links"]?.array ?? []).compactMap(GoogleLinkRound.init)
    }

    /// This block's round (its `text/<id>.jsonl` path in the data folder), if the hub has one.
    public func link(for path: String) -> GoogleLinkRound? { links.first { $0.path == path } }
}

/// One linked block's last round on the hub.
public struct GoogleLinkRound: Equatable, Sendable {
    public var path: String
    public var state: String?
    public var at: String?
    public var error: String?
    public var kind: String?
    public var tabs: Int?
    public var comments: Int?
    public var suggestions: Int?

    public init?(_ v: JSONValue) {
        guard let p = v["path"]?.string else { return nil }
        path = p
        state = v["state"]?.string
        at = v["at"]?.string
        error = v["error"]?.string
        kind = v["kind"]?.string
        tabs = v["tabs"]?.number.map { Int($0) }
        comments = v["comments"]?.number.map { Int($0) }
        suggestions = v["suggestions"]?.number.map { Int($0) }
    }
}

/// What the Google Docs panel says about one block's link (gpanel.js `panelModel`).
public struct GooglePanel: Equatable, Sendable {
    public enum Tone: String, Sendable { case off, idle, busy, ok, warn }
    public enum Act: String, CaseIterable, Sendable { case settings, make, link, push, pull, open, sync, retry, unlink }

    public var tone: Tone
    public var head: String
    public var lines: [String]
    public var actions: [Act]

    /// The bridge's own words when both sides have words (gpanel.js `BOTH_WORDS`).
    public static let bothWords = "Both this block and the Doc have words. Choose which to keep."

    public static func model(g: GoogleDocLink?, hub: GoogleHubState?, link: GoogleLinkRound?, now: Date = Date()) -> GooglePanel {
        var lines: [String] = []
        var off: (head: String, line: String)?
        if let hub, hub.state == "nohub" {
            off = ("Sync with the hub is not set up", "Google Docs runs on the hub. Set up Settings › Sync first, then connect Google Docs on the laptop.")
        } else if let hub, hub.state == "ok", hub.enabled == false {
            off = ("The hub has no Google Docs", "Update the hub, then connect Google Docs in the laptop's Settings › Sync.")
        } else if let hub, hub.state == "ok", !hub.connected {
            off = ("Google Docs is not connected", "Connect it in the laptop's Settings › Sync. The hub then keeps linked blocks and their Docs in step.")
        }
        if let off, g == nil { return .init(tone: .off, head: off.head, lines: [off.line], actions: [.settings]) }
        if let hub, hub.state == "error" {
            lines.append("Can't reach the hub right now" + (hub.error.map { " (\($0))" } ?? "") + ". What is shown here may be out of date.")
        }
        guard let g else {
            return .init(tone: .idle, head: "Not linked to a Google Doc",
                         lines: ["Make a new Doc from this block, or link one you already have. From then on the hub keeps the two in step, both ways."] + lines,
                         actions: [.make, .link])
        }
        if let off {
            return .init(tone: .off, head: off.head, lines: [off.line, "This block stays linked; nothing goes either way until then."],
                         actions: [.settings] + (g.url != nil ? [.open] : []) + [.unlink])
        }
        if g.error == bothWords || link?.kind == "both" {
            return .init(tone: .warn, head: "Both have words",
                         lines: ["This block and the Doc both have words. Choose which to keep; the other side's words are replaced."] + lines,
                         actions: [.push, .pull, .unlink])
        }
        if let e = g.error {
            return .init(tone: .warn, head: "Not in step", lines: [e] + lines, actions: (g.url != nil ? [.open] : []) + [.retry, .unlink])
        }
        guard g.url != nil else {
            return .init(tone: .busy, head: g.create ? "Making the Doc…" : "Linking…",
                         lines: ["The hub is " + (g.create ? "making the Doc" : "opening the Doc") + ". This takes a few seconds."] + lines,
                         actions: [.unlink])
        }
        var tone = Tone.ok
        if link?.state == "error", let e = link?.error { tone = .warn; lines.insert("Last round failed: " + e, at: 0) }
        else if link?.state == "off" { tone = .warn; lines.insert(link?.error ?? "Google Docs is not connected on the hub.", at: 0) }
        else if let at = link?.at { lines.insert("In step. Last checked " + ago(at, now: now) + ".", at: 0) }
        else { lines.insert("Waiting for the hub's first round.", at: 0) }
        return .init(tone: tone, head: g.title ?? "Untitled document", lines: lines, actions: [.open, .sync, .unlink])
    }

    /// "just now", "3 minutes ago", "2 hours ago", else the day ("12 Nov") (gpanel.js `ago`).
    public static func ago(_ iso: String, now: Date = Date()) -> String {
        guard let t = parse(iso) else { return "" }
        let s = max(0, Int((now.timeIntervalSince(t)).rounded()))
        if s < 45 { return "just now" }
        let m = Int((Double(s) / 60).rounded())
        if m < 60 { return m == 1 ? "a minute ago" : "\(m) minutes ago" }
        let h = Int((Double(m) / 60).rounded())
        if h < 24 { return h == 1 ? "an hour ago" : "\(h) hours ago" }
        let c = Calendar.current.dateComponents([.day, .month], from: t)
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(c.day ?? 1) \(months[max(0, min(11, (c.month ?? 1) - 1))])"
    }

    static func parse(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }
}
