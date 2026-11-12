import Foundation
#if canImport(JavaScriptCore)
import JavaScriptCore
#endif

/// A typed block's words as two files, the same as the laptop (nexus docs/rich-text.md): `text/<id>.jsonl` (what Nexus keeps: paragraph
/// ids, who wrote what, the header with the Google Docs link and tabs) and `text/<id>.md` (the readable copy, the words the board holds).
/// The laptop's own converters (renderer/src/board/richblock.js, bundled by tools/richtext/build.mjs into Resources/richcore.js) run here
/// in JavaScriptCore, with no web page, so both apps and the hub's Google Docs bridge read and write the .jsonl the same way.
/// The copy is written plain (no checksum line), as the laptop writes it until the hub merges blocks by the .jsonl.
public final class RichWords: @unchecked Sendable {
    /// Who the iPad credits a paragraph it changed to: its sync name (Settings › Sync), "iPad" until one is set.
    public static var device: String {
        get { deviceOverride ?? UserDefaults.standard.string(forKey: "sync.deviceName").flatMap { $0.isEmpty ? nil : $0 } ?? "iPad" }
        set { deviceOverride = newValue }
    }
    private static var deviceOverride: String?
    /// Off in tests that want the files as they were before the switch.
    public static var enabled = true

    public static let shared = RichWords()

    private let lock = NSLock()
    #if canImport(JavaScriptCore)
    private var context: JSContext?
    private var core: JSValue?
    #endif
    private var failed = false
    /// The last thing that went wrong, for diagnostics.
    public private(set) var lastError: String?

    /// `text/<id>.jsonl` for a block (drafts keep only their .md, as on the laptop).
    public static func docFile(_ id: String) -> String { "text/\(id).jsonl" }

    /// Whether a text key is a block's own words (not another draft or a snapshot).
    public static func isMain(_ key: String) -> Bool { !key.contains("~") }

    /// ISO time now, as the laptop stamps a paragraph's `at`.
    public static func now() -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    // MARK: the converters

    public struct Read: Equatable, Sendable {
        /// The block's words, as the board holds them.
        public var md: String
        /// 'json' (the .jsonl as it was), 'outside' (the copy was edited outside Nexus and read into the doc), 'converted' (a block made
        /// before the switch), 'new' (neither file), 'jsonl' (the .jsonl is newer than its copy: its words), or 'plain' (no converter).
        public var how: String
        /// The .jsonl should be written again.
        public var stale: Bool
    }

    /// What is on disk (either may be nil) -> the block's words. `jsonlNewer`: the .jsonl was written after its copy (the Google Docs
    /// bridge or another device wrote only the .jsonl): its words win over a copy that says something else.
    public func read(jsonl: String?, file: String?, jsonlNewer: Bool = false) -> Read {
        if let jsonl, jsonlNewer, !jsonl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let w = words(jsonl) {
            return Read(md: w, how: "jsonl", stale: false)
        }
        if let r = call("read", [jsonl ?? NSNull(), file ?? NSNull(), RichWords.device, RichWords.now()]),
           r["ok"] as? Bool == true, let md = r["md"] as? String {
            return Read(md: md, how: r["how"] as? String ?? "json", stale: r["stale"] as? Bool ?? false)
        }
        return Read(md: RichWords.body(file ?? ""), how: "plain", stale: jsonl == nil && file != nil)
    }

    /// The .jsonl for the words `md`, following the doc last read or written (`prevJsonl`, which held the words `prevMd`) so paragraph ids,
    /// who wrote them and the header stay. Nil when it can't be made (the old .jsonl is then kept as it is).
    public func write(md: String, prevJsonl: String?, prevMd: String?) -> String? {
        guard let r = call("write", [md, prevJsonl ?? NSNull(), prevMd ?? NSNull(), RichWords.device, RichWords.now()]), r["ok"] as? Bool == true else { return nil }
        return r["jsonl"] as? String
    }

    /// A .jsonl's words, as the block holds them; nil when it can't be read.
    public func words(_ jsonl: String) -> String? {
        guard let r = call("words", [jsonl]), r["ok"] as? Bool == true else { return nil }
        return r["md"] as? String
    }

    /// A .jsonl's header (the Google link, tabs), as JSON.
    public func header(_ jsonl: String) -> JSONValue? {
        guard let line = jsonl.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first else { return nil }
        return try? JSONValue.parse(String(line))
    }

    /// The .jsonl with one header key set (JSON text; nil takes it off), the words kept.
    public func setHeader(_ jsonl: String, key: String, json: String?) -> String? {
        guard let r = call("setHeader", [jsonl, key, json ?? NSNull()]), r["ok"] as? Bool == true else { return nil }
        return r["jsonl"] as? String
    }

    /// A copy's words: its checksum line (`<!-- nexus-copy … -->`, written by a newer Nexus) taken off; Windows line ends read as plain.
    public static func body(_ file: String) -> String {
        var s = file.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if let r = s.range(of: #"\n*<!-- nexus-copy [^\n]*-->\s*$"#, options: .regularExpression) { s.removeSubrange(r) }
        return s
    }

    // MARK: JavaScriptCore

    private func call(_ name: String, _ args: [Any]) -> [String: Any]? {
        guard RichWords.enabled else { return nil }
        lock.lock(); defer { lock.unlock() }
        #if canImport(JavaScriptCore)
        guard let core = load(), let fn = core.objectForKeyedSubscript(name), let out = fn.call(withArguments: args), out.isString,
              let text = out.toString(), let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if let e = context?.exception { lastError = e.toString(); context?.exception = nil }
            return nil
        }
        if obj["ok"] as? Bool == false { lastError = obj["error"] as? String }
        return obj
        #else
        return nil
        #endif
    }

    #if canImport(JavaScriptCore)
    private func load() -> JSValue? {
        if let core { return core }
        if failed { return nil }
        guard let url = Bundle.module.url(forResource: "richcore", withExtension: "js"), let code = try? String(contentsOf: url, encoding: .utf8),
              let ctx = JSContext() else { failed = true; lastError = "richcore.js is missing"; return nil }
        ctx.exceptionHandler = { [weak self] _, e in self?.lastError = e?.toString() }
        ctx.evaluateScript(code, withSourceURL: url)
        guard let c = ctx.objectForKeyedSubscript("NexusRichCore"), c.isObject else { failed = true; lastError = lastError ?? "richcore.js did not load"; return nil }
        context = ctx
        core = c
        return c
    }
    #endif
}
