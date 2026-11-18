import Foundation

// "Get deadlines from the school's site" (the laptop's sitefacts.js), the pure half: the app fetches the admissions page, follows up to 3 same-site
// links about deadlines or requirements (pickLinks), makes one Claude call without tools (prompt -> parse), keeps only what the pages really say
// (verify) and compares it with the school's file (diff). Nothing is written until the user reviews it; apply is what Save selected writes.
// The cycle (cycleOf) runs 1 Aug to 31 Jul: from April on, the one starting this August; in January to March, the one that started last August.

public enum SiteFacts {
    public static let maxLinks = 3
    public static let pageChars = 12000
    static let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]

    // MARK: regex helpers

    static func re(_ p: String, _ o: NSRegularExpression.Options = [.caseInsensitive]) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: o) }
    static func replace(_ s: String, _ r: NSRegularExpression, _ with: String) -> String {
        r.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: with)
    }
    static func test(_ r: NSRegularExpression, _ s: String) -> Bool { r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }

    // MARK: HTML to text

    static let entities: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "rsquo": "\u{2019}", "lsquo": "\u{2018}",
                                             "ldquo": "\u{201C}", "rdquo": "\u{201D}", "ndash": "\u{2013}", "mdash": "\u{2014}", "hellip": "\u{2026}", "middot": "\u{B7}",
                                             "bull": "\u{2022}", "copy": "\u{A9}", "reg": "\u{AE}", "trade": "\u{2122}", "shy": ""]
    static let entityRe = re(#"&(#x[0-9a-f]+|#\d+|[a-z]+);"#)
    public static func decodeEntities(_ s: String) -> String {
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in entityRe.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let e = ns.substring(with: m.range(at: 1))
            var rep: String?
            if e.hasPrefix("#") {
                let hex = e.dropFirst().first.map { $0 == "x" || $0 == "X" } ?? false
                let n = hex ? UInt32(e.dropFirst(2), radix: 16) : UInt32(e.dropFirst())
                if let n, n > 0, n < 0x110000, let u = Unicode.Scalar(n) { rep = String(Character(u)) }
            } else { rep = entities[e.lowercased()] }
            out += rep ?? ns.substring(with: m.range)
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    static let commentRe = re(#"<!--[\s\S]*?-->"#)
    static let hiddenRe = re(#"<(script|style|noscript|template|svg|head|iframe|object)\b[\s\S]*?</\1\s*>"#)
    static let blockRe = re(#"</?(?:p|div|br|li|ul|ol|h[1-6]|tr|td|th|thead|tbody|table|section|article|header|footer|nav|main|aside|dd|dt|dl|blockquote|pre|hr|form|fieldset|figure|figcaption|caption|details|summary|option|label|button)\b[^>]*>"#)
    static let tagRe = re(#"<[^>]*>"#)
    static let spaceRe = re("[ \\t\\f\\v\\r\u{A0}\u{2000}-\u{200B}\u{2028}\u{2029}\u{3000}]+", [])

    /// The readable text of a page: scripts, styles and comments gone, a line per block, entities decoded, spaces collapsed.
    public static func htmlToText(_ html: String) -> String {
        var s = replace(html, commentRe, " ")
        s = replace(s, hiddenRe, " ")
        s = replace(s, blockRe, "\n")
        s = replace(s, tagRe, "")
        s = decodeEntities(s)
        return s.components(separatedBy: "\n").map { replace($0, spaceRe, " ").trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    // MARK: links worth following

    /// The site of a host: its last two labels (columbia.edu), three under a two-letter country code with a short label (ox.ac.uk).
    public static func siteOf(_ host: String) -> String {
        var h = host.lowercased()
        if h.hasSuffix(".") { h.removeLast() }
        let p = h.split(separator: ".").map(String.init)
        if p.count <= 2 { return p.joined(separator: ".") }
        return p[p.count - 1].count == 2 && p[p.count - 2].count <= 3 ? p.suffix(3).joined(separator: ".") : p.suffix(2).joined(separator: ".")
    }
    public static func urlKey(_ u: String) -> String {
        guard var c = URLComponents(string: u), let scheme = c.scheme, let host = c.host else { return u }
        c.fragment = nil
        var path = c.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        let h = host.lowercased().replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
        return scheme + "://" + h + (c.port.map { ":\($0)" } ?? "") + path + (c.percentEncodedQuery.map { "?" + $0 } ?? "")
    }
    public static func hostOf(_ u: String) -> String {
        (URL(string: u)?.host ?? "").replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
    }

    static let linkKinds: [(Int, NSRegularExpression)] = [
        (3, re(#"deadline|key dates|important dates|\bdates\b|calendar|timeline"#)),
        (2, re(#"requirement|first[- ]?year|freshman|checklist|testing|test[- ]optional|\bsat\b|\bact\b"#)),
        (1, re(#"\bapply\b|applying|application|admission plans|early decision|early action|regular decision"#)),
    ]
    static let notAPage = re(#"\.(pdf|docx?|xlsx?|pptx?|jpe?g|png|gif|svg|webp|zip|mp4|mp3)$"#)
    static let anchorRe = re(#"<a\b([^>]*)>([\s\S]*?)</a\s*>"#)
    static let hrefRe = re(#"\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#)
    static let ariaRe = re(#"\baria-label\s*=\s*"([^"]*)""#)
    static let skipHref = re(#"^(#|mailto:|tel:|javascript:)"#)

    public struct Link: Equatable { public var url, name: String }

    /// Up to `max` links on the same site about deadlines, dates, requirements, first-year or applying, the best first.
    public static func pickLinks(_ html: String, base baseUrl: String, max: Int = maxLinks) -> [Link] {
        guard let base = URL(string: baseUrl), let bhost = base.host else { return [] }
        let site = siteOf(bhost), me = urlKey(base.absoluteString)
        struct Seen { var url, name: String; var score, i: Int }
        var seen: [String: Seen] = [:]
        var i = 0
        let ns = html as NSString
        for m in anchorRe.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let attrs = ns.substring(with: m.range(at: 1)), inner = ns.substring(with: m.range(at: 2))
            let an = attrs as NSString
            guard let hm = hrefRe.firstMatch(in: attrs, range: NSRange(location: 0, length: an.length)) else { continue }
            let g = (1...3).first { hm.range(at: $0).location != NSNotFound } ?? 1
            let href = decodeEntities(an.substring(with: hm.range(at: g))).trimmingCharacters(in: .whitespaces)
            if href.isEmpty || test(skipHref, href) { continue }
            guard let u0 = URL(string: href, relativeTo: base)?.absoluteURL, let scheme = u0.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  let h = u0.host, siteOf(h) == site, !test(notAPage, u0.path) else { continue }
            var c = URLComponents(url: u0, resolvingAgainstBaseURL: true)
            c?.fragment = nil
            let url = c?.url?.absoluteString ?? u0.absoluteString
            let key = urlKey(url)
            if key == me { continue }
            let label = ariaRe.firstMatch(in: attrs, range: NSRange(location: 0, length: an.length)).map { an.substring(with: $0.range(at: 1)) }
            var name = htmlToText(inner).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            if name.isEmpty, let label { name = decodeEntities(label).trimmingCharacters(in: .whitespaces) }
            let pathWords = (u0.path.removingPercentEncoding ?? u0.path).replacingOccurrences(of: #"[-_/]+"#, with: " ", options: .regularExpression)
            let hay = name + " " + pathWords
            let score = linkKinds.reduce(0) { $0 + (test($1.1, hay) ? $1.0 : 0) }
            if score == 0 { continue }
            if var prev = seen[key] {
                if score > prev.score { prev.score = score; if !name.isEmpty { prev.name = String(name.prefix(60)) }; seen[key] = prev }
            } else {
                let fallback = u0.path.split(separator: "/").last.map(String.init) ?? h
                seen[key] = Seen(url: url, name: String((name.isEmpty ? fallback : name).prefix(60)), score: score, i: i)
                i += 1
            }
        }
        return seen.values.sorted { $0.score != $1.score ? $0.score > $1.score : $0.i < $1.i }.prefix(max).map { Link(url: $0.url, name: $0.name) }
    }

    // MARK: the cycle

    public struct Cycle: Equatable { public var start, end: String; public var year: Int }
    public static func cycleOf(_ today: String) -> Cycle {
        let p = today.split(separator: "-").compactMap { Int($0) }
        let y = p.first ?? 2026, m = p.count > 1 ? p[1] : 1
        let Y = m >= 4 ? y : y - 1
        return Cycle(start: "\(Y)-08-01", end: "\(Y + 1)-07-31", year: Y)
    }

    // MARK: the Claude call

    public static let system = "You read web pages and report facts from them as JSON. You only use what the pages say, and you copy every sentence you cite exactly as it is written on the page."
    public struct Page: Equatable { public var url, text: String; public init(url: String, text: String) { self.url = url; self.text = text } }

    public static func prompt(pages: [Page], name: String, today: String) -> String {
        let c = cycleOf(today)
        let body = pages.enumerated().map { i, p in
            let t = p.text.count > pageChars ? String(p.text.prefix(pageChars)) + "\n[... the rest of the page is cut]" : p.text
            return "=== Page \(i + 1): \(p.url) ===\n\(t)\n=== End of page \(i + 1) ==="
        }.joined(separator: "\n\n")
        return [
            "Read the admissions pages of \(name.isEmpty ? "a university" : name) below (Nexus site check) and report its application rounds, their deadlines and what a first-year applicant must send.",
            "Today is \(today). This admissions cycle runs from \(c.start) to \(c.end): report only deadlines in it.",
            "",
            "Rules:",
            "- Use only what the pages below say. Never guess, never add what you know about the school from elsewhere.",
            "- Every item needs \"quote\": one sentence (or table row) copied exactly from a page, and \"url\": that page's address exactly as given in its === Page line. Items whose quote is not on its page are thrown away.",
            "- Rounds: \"ed\" = Early Decision, \"ed2\" = Early Decision II, \"ea\" = Early Action (restrictive or single-choice early action too), \"rd\" = Regular Decision. \"date\" is the application deadline as YYYY-MM-DD, in this cycle; the quote must contain that date.",
            "- \"notOffered\": the rounds the pages say the school does not offer (only when they say so).",
            "- \"requirements\": short names of what a first-year applicant must send (for example \"Two teacher recommendations\"), each with its quote.",
            "- \"testing\": the testing policy in a few words with its quote, or null.",
            "- Leave a list empty when the pages do not say.",
            "",
            "Reply with JSON only, no other text, in this shape:",
            "{\"rounds\":[{\"round\":\"ed\",\"date\":\"YYYY-MM-DD\",\"quote\":\"...\",\"url\":\"...\"}],\"notOffered\":[\"ed2\"],\"requirements\":[{\"text\":\"...\",\"quote\":\"...\",\"url\":\"...\"}],\"testing\":{\"text\":\"...\",\"quote\":\"...\",\"url\":\"...\"}}",
            "",
            body,
        ].joined(separator: "\n")
    }

    static let fenceRe = re(#"```(?:json|JSON)?\s*\n?([\s\S]*?)```"#, [])
    /// The first JSON object in a reply (a fenced block, else the text from the first `{` to the last `}`), or nil.
    public static func jsonObject(_ text: String) -> JSONValue? {
        let ns = text as NSString
        var cands = fenceRe.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
        if let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}"), a < b { cands.append(String(text[a...b])) }
        for c in cands {
            if let v = try? JSONValue.parse(c.trimmingCharacters(in: .whitespacesAndNewlines)), v.object != nil { return v }
        }
        return nil
    }

    public struct FoundRound: Equatable { public var round, date, quote, url: String }
    public struct FoundItem: Equatable { public var text, quote, url: String }
    public struct Found: Equatable {
        public var rounds: [FoundRound] = []
        public var notOffered: [String] = []
        public var requirements: [FoundItem] = []
        public var testing: FoundItem?
    }

    static func str(_ v: JSONValue?) -> String { (v?.text1 ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    static func item(_ x: JSONValue?) -> FoundItem? {
        guard let x, x.object != nil else { return nil }
        return FoundItem(text: str(x["text"] ?? x["name"] ?? x["t"]), quote: str(x["quote"]), url: str(x["url"]))
    }

    /// Claude's reply as findings, or nil when it holds no JSON object.
    public static func parse(_ text: String) -> Found? {
        guard let j = jsonObject(text) else { return nil }
        var f = Found()
        f.rounds = (j["rounds"]?.array ?? []).filter { $0.object != nil }
            .map { FoundRound(round: str($0["round"]).lowercased(), date: String(str($0["date"]).prefix(10)), quote: str($0["quote"]), url: str($0["url"])) }
            .filter { Apps.roundKeys.contains($0.round) }
        var seen = Set<String>()
        f.notOffered = (j["notOffered"]?.array ?? []).map { str($0).lowercased() }.filter { Apps.roundKeys.contains($0) && seen.insert($0).inserted }
        f.requirements = (j["requirements"]?.array ?? []).compactMap { item($0) }.filter { !$0.text.isEmpty }
        if let t = item(j["testing"]), !t.text.isEmpty { f.testing = t }
        return f
    }

    // MARK: verify

    static let notWord = re(#"[^\p{L}\p{N}]+"#, [])
    /// Lower-cased, curly quotes and dashes plain, every run of punctuation or space one space.
    public static func norm(_ s: String) -> String {
        var t = s.lowercased()
        for c in ["\u{2018}", "\u{2019}", "\u{201A}", "\u{201B}", "\u{2032}", "`"] { t = t.replacingOccurrences(of: c, with: "'") }
        for c in ["\u{201C}", "\u{201D}", "\u{201E}", "\u{201F}", "\u{2033}"] { t = t.replacingOccurrences(of: c, with: "\"") }
        return replace(t, notWord, " ").trimmingCharacters(in: .whitespaces)
    }

    /// Does a round's sentence name its date (the month by name or abbreviation and the day, or 11/1)?
    public static func dateInQuote(_ date: String, _ quote: String) -> Bool {
        let p = date.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]) else { return false }
        let m = p[1], d = p[2], q = norm(quote), name = months[m - 1]
        let month = test(re("\\b(\(name)|\(name.prefix(3))\(name == "september" ? "|sept" : ""))\\b", []), q)
        let day = test(re("\\b0?\(d)(st|nd|rd|th)?\\b", []), q)
        return (month && day) || test(re("(^|[^\\d])0?\(m)[/.-]0?\(d)([^\\d]|$)", []), quote)
    }

    public struct Dropped: Equatable { public var kind, label, why: String }
    public struct Kept: Equatable {
        public var rounds: [FoundRound] = []
        public var notOffered: [String] = []
        public var requirements: [FoundItem] = []
        public var testing: FoundItem?
        public var dropped: [Dropped] = []
    }

    static func isDay(_ s: String) -> Bool { s.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil && Days.isIso(s) }

    /// Only the items whose quote is on its page (any fetched page when its url is not one of them: the item then takes that page's url) and whose
    /// date is in this cycle.
    public static func verify(_ found: Found?, pages: [Page], cycle: Cycle) -> Kept {
        let P = pages.map { (url: $0.url, key: urlKey($0.url), text: " " + norm($0.text) + " ") }
        var k = Kept()
        func place(_ quote: String, _ url: String) -> String? {
            let q = norm(quote)
            guard q.split(separator: " ").count >= 3 else { return nil }
            func has(_ p: (url: String, key: String, text: String)) -> Bool { p.text.contains(" " + q + " ") }
            if let own = P.first(where: { $0.key == urlKey(url) }) { return has(own) ? own.url : nil }
            return P.first(where: has)?.url
        }
        var have = Set<String>()
        for r in found?.rounds ?? [] {
            let label = "\(Apps.roundNames[r.round] ?? r.round.uppercased()) \(r.date)"
            guard isDay(r.date) else { k.dropped.append(Dropped(kind: "round", label: label, why: "no date")); continue }
            guard let url = place(r.quote, r.url) else { k.dropped.append(Dropped(kind: "round", label: label, why: "quote not on the page")); continue }
            if r.date < cycle.start || r.date > cycle.end { k.dropped.append(Dropped(kind: "round", label: label, why: "outside this cycle")); continue }
            if !dateInQuote(r.date, r.quote) { k.dropped.append(Dropped(kind: "round", label: label, why: "date not in its sentence")); continue }
            if !have.insert(r.round).inserted { continue }
            var x = r; x.url = url; k.rounds.append(x)
        }
        var seen = Set<String>()
        for r in found?.requirements ?? [] {
            guard let url = place(r.quote, r.url) else { k.dropped.append(Dropped(kind: "req", label: r.text, why: "quote not on the page")); continue }
            if !seen.insert(norm(r.text)).inserted { continue }
            var x = r; x.url = url; k.requirements.append(x)
        }
        if let t = found?.testing {
            if let url = place(t.quote, t.url) { var x = t; x.url = url; k.testing = x } else { k.dropped.append(Dropped(kind: "test", label: t.text, why: "quote not on the page")) }
        }
        k.notOffered = (found?.notOffered ?? []).filter { !have.contains($0) }
        return k
    }

    // MARK: compare with the file

    static let mon = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    public static func fmtDate(_ iso: String, year: Bool = true) -> String {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]) else { return iso }
        return "\(p[2]) \(mon[p[1] - 1])\(year ? " \(p[0])" : "")"
    }

    public struct Finding: Identifiable, Equatable {
        public enum Kind: String { case round, none, req, test }
        public var kind: Kind
        public var key = ""
        public var keys: [String] = []
        public var label: String
        public var value = "", display = "", quote = "", url = ""
        /// "new", "same" or "changed" (nothing for `none`).
        public var status = ""
        public var was: String?
        public var legacy = false
        /// To be saved (new or changed).
        public var on = false
        public var id: String { kind.rawValue + ":" + (key.isEmpty ? label : key) }
    }

    /// The review's items, in order: the rounds (same / changed / new), "not offered", the requirements and the testing policy.
    public static func diff(_ kept: Kept, school: School) -> [Finding] {
        let R = school.research.rounds
        let known = Set((school.research.reqs.map(\.t) + school.requirements.map(\.t)).map(norm))
        var out: [Finding] = []
        for k in Apps.roundKeys {
            guard let r = kept.rounds.first(where: { $0.round == k }) else { continue }
            let mine = R[k]?.dl
            let status = mine == nil ? "new" : mine == r.date ? "same" : "changed"
            out.append(Finding(kind: .round, key: k, label: "\(Apps.roundNames[k] ?? k) deadline", value: r.date, display: fmtDate(r.date), quote: r.quote, url: r.url,
                               status: status, was: status == "changed" ? mine : nil, legacy: R[k]?.legacy ?? false))
        }
        if !kept.notOffered.isEmpty {
            out.append(Finding(kind: .none, keys: kept.notOffered, label: "Not offered: \(kept.notOffered.map { Apps.roundNames[$0] ?? $0 }.joined(separator: ", ")).", status: ""))
        }
        for r in kept.requirements {
            out.append(Finding(kind: .req, label: r.text, quote: r.quote, url: r.url, status: known.contains(norm(r.text)) ? "same" : "new"))
        }
        if let t = kept.testing {
            let label = "Testing: \(t.text)"
            out.append(Finding(kind: .test, label: label, quote: t.quote, url: t.url, status: known.contains(norm(label)) ? "same" : "new"))
        }
        return out.map { f in var x = f; if x.kind != .none { x.on = x.status != "same" }; return x }
    }

    /// What Save selected writes: `raw` is the school's `research` as written; `take` the chosen items. -> the new research and the requirements added
    /// (for an applying school's checklist too).
    public static func apply(_ raw: JSONValue, take: [Finding], today: String) -> (research: JSONValue, reqs: [(t: String, src: String)]) {
        var r: JSONValue = raw.object != nil ? raw : .object([])
        var rounds: JSONValue = r["rounds"]?.object != nil ? r["rounds"]! : .object([])
        var sources: JSONValue = r["sources"]?.object != nil ? r["sources"]! : .object([])
        var reqs: [JSONValue] = r["reqs"]?.array ?? []
        var has = Set(reqs.map { norm($0.object != nil ? ($0["t"]?.text1 ?? "") : ($0.text1 ?? "")) })
        var added: [(t: String, src: String)] = []
        for f in take {
            if f.kind == .round, Apps.roundKeys.contains(f.key), isDay(f.value) {
                let cur: JSONValue = rounds[f.key]?.object != nil ? rounds[f.key]! : .object([])
                rounds = rounds.setting(f.key, cur.setting("dl", .string(f.value)))
                sources = sources.setting("\(Apps.roundNames[f.key] ?? f.key) date", .string(f.url))
            } else if f.kind == .req || f.kind == .test {
                if has.insert(norm(f.label)).inserted {
                    reqs.append(.object([("t", .string(f.label)), ("src", .string(f.url))]))
                    added.append((f.label, f.url))
                }
                sources = sources.setting(f.kind == .test ? "Testing" : "Requirements", .string(f.url))
            }
        }
        r = r.setting("rounds", rounds).setting("sources", sources).setting("reqs", reqs.isEmpty ? nil : .array(reqs)).setting("checked", .string(today))
        return (r, added)
    }
}
