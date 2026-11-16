import Foundation

/// Something shared into Nexus from another app (Safari, Photos, Files, Mail) through the "Save to Nexus" action, which a Shortcut
/// set to show in the Share Sheet runs: what it is, and where it lands. A PDF or a picture becomes a board in a notebook (the
/// notebook "Shared" unless the Shortcut names another); a link or some words become a task in the Inbox.
public enum Shared {
    public enum Kind: Equatable {
        case pdf
        case image
        /// A web address, read out of a link file or plain text.
        case link(String)
        /// Words (the first line is the task's title, the rest its note).
        case text(String)
        /// Nothing Nexus can keep (a video, an unknown file).
        case unknown
    }

    /// The notebook shared files go into when the Shortcut names none.
    public static let defaultNotebook = "Shared"

    static let imageExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp"]
    static let textExts: Set<String> = ["txt", "text", "md", "markdown", "url", "webloc", ""]

    /// What a shared file is, from its type identifier (`com.adobe.pdf`, `public.jpeg`, `public.url`…), its name, and its bytes.
    public static func kind(typeId: String?, name: String, data: Data) -> Kind {
        let t = (typeId ?? "").lowercased()
        let ext = (name as NSString).pathExtension.lowercased()
        if t == "com.adobe.pdf" || ext == "pdf" || data.starts(with: Array("%PDF".utf8)) { return .pdf }
        if t.hasPrefix("public.") && imageTypes.contains(t) || imageExts.contains(ext) { return .image }
        if let u = webloc(data) { return .link(u) }
        if t == "public.html" || ext == "html" || ext == "htm" || t == "com.apple.webarchive" {
            // a web page Shortcuts fetched for the address it was given: keep the page's own address and title
            guard let html = String(data: data.prefix(400_000), encoding: .utf8) ?? String(data: data.prefix(400_000), encoding: .isoLatin1)
            else { return .unknown }
            if let u = pageAddress(html) { return .link(u) }
            if let title = pageTitle(html) { return .text(title) }
            return .unknown
        }
        let isText = t.isEmpty || t == "public.url" || t.hasPrefix("public.") && (t.contains("text") || t == "public.utf8-plain-text")
            || textExts.contains(ext)
        guard isText, data.count < 200_000, let s = String(data: data, encoding: .utf8) else { return .unknown }
        return kind(text: s)
    }

    static let imageTypes: Set<String> = ["public.image", "public.jpeg", "public.png", "public.heic", "public.heif", "public.tiff",
                                          "com.compuserve.gif", "com.microsoft.bmp", "org.webmproject.webp"]

    /// Words shared as they are: a lone web address is a link, anything else is text; nil when there is nothing but space.
    public static func kind(text: String) -> Kind {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return .unknown }
        // a Windows .url file: "[InternetShortcut]\nURL=https://…"
        if s.hasPrefix("[InternetShortcut]"), let line = s.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("URL=") }) {
            return .link(String(line.dropFirst(4)))
        }
        if !s.contains(where: \.isWhitespace), let u = URL(string: s), let scheme = u.scheme?.lowercased(),
           ["http", "https", "mailto", "onenote"].contains(scheme) {
            return .link(s)
        }
        return .text(s)
    }

    /// A web page's own address: its canonical link or og:url.
    public static func pageAddress(_ html: String) -> String? {
        for pattern in [#"<link[^>]+rel=["']canonical["'][^>]*href=["']([^"']+)["']"#, #"<link[^>]+href=["']([^"']+)["'][^>]*rel=["']canonical["']"#,
                        #"<meta[^>]+property=["']og:url["'][^>]*content=["']([^"']+)["']"#] {
            if let m = first(pattern, in: html), m.hasPrefix("http") { return m }
        }
        return nil
    }

    /// A web page's title (og:title, else <title>), its entities read.
    public static func pageTitle(_ html: String) -> String? {
        let raw = first(#"<meta[^>]+property=["']og:title["'][^>]*content=["']([^"']+)["']"#, in: html)
            ?? first(#"<title[^>]*>([^<]+)</title>"#, in: html)
        guard let raw else { return nil }
        let t = oneLine(raw.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">"))
        return t.isEmpty ? nil : t
    }

    static func first(_ pattern: String, in s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    /// A Mac's .webloc (a property list with a URL key).
    static func webloc(_ data: Data) -> String? {
        guard data.starts(with: Array("bplist".utf8)) || data.starts(with: Array("<?xml".utf8)),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let u = plist["URL"] as? String else { return nil }
        return u
    }

    /// The Inbox task for a link or words: its title (one line, at most 200 characters) and the note that keeps the rest.
    /// A link's title is the address itself, so the laptop and the phone show it as a link; a page's title, when the Shortcut
    /// passes one, goes first.
    public static func task(_ k: Kind, pageTitle: String? = nil) -> (title: String, note: String?)? {
        switch k {
        case .link(let u):
            let t = pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty || t == u ? (u, nil) : (oneLine(t), u)
        case .text(let s):
            let lines = s.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let first = oneLine(lines.first ?? s)
            let rest = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let cut = first.count > 200
            let title = cut ? String(first.prefix(199)) + "…" : first
            let note = [cut ? first : nil, rest.isEmpty ? nil : rest].compactMap { $0 }.joined(separator: "\n\n")
            return (title, note.isEmpty ? nil : note)
        default:
            return nil
        }
    }

    static func oneLine(_ s: String) -> String {
        s.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    /// A notebook name a Shortcut typed, made safe for a folder name (no slashes or the characters Windows refuses); the default
    /// when nothing is left.
    public static func notebook(_ want: String?) -> String {
        let bad = Set("/\\<>:\"|?*")
        let s = String((want ?? "").filter { !bad.contains($0) && !$0.isNewline })
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return s.isEmpty ? defaultNotebook : s
    }

    /// The board's name for a shared file: its name without the extension, or "Shared PDF" / "Shared photo" for a nameless one
    /// (Photos passes "IMG_0412.HEIC", Safari's PDF view passes "file.pdf").
    public static func boardName(fileName: String, kind: Kind) -> String {
        let stem = (fileName as NSString).deletingPathExtension.trimmingCharacters(in: .whitespaces)
        if stem.isEmpty || ["file", "image", "untitled", "document"].contains(stem.lowercased()) {
            return kind == .pdf ? "Shared PDF" : "Shared photo"
        }
        return stem
    }
}
