import Foundation
#if canImport(JavaScriptCore)
import JavaScriptCore
#endif

/// A task's Activity, in the laptop's own words (nexus renderer/src/activity.js, bundled by tools/activity/build.mjs into
/// Resources/activitycore.js and run here in JavaScriptCore): what happened to the task, from its file's facts (added, ticked) and the
/// data folder's git history, which the hub on the G14 keeps and answers at `GET /v2/activity?path=&id=&limit=30` (the laptop's
/// desktop/backend/src/activity.rs shape: `{repo, versions: [{hash, at, author, path, text}], trail: [{hash, at, author, files}]}`).
public final class TaskActivity: @unchecked Sendable {
    public struct Row: Equatable, Sendable {
        public var at: String?
        /// The app day it happened (YYYY-MM-DD).
        public var date: String?
        public var text: String
        /// "Claude" for a change Claude made, else nil (you).
        public var who: String?
        public init(at: String?, date: String?, text: String, who: String?) { self.at = at; self.date = date; self.text = text; self.who = who }
    }

    public static let shared = TaskActivity()
    private let lock = NSLock()
    #if canImport(JavaScriptCore)
    private var core: JSValue?
    private var context: JSContext?
    #endif
    private var failed = false
    public private(set) var lastError: String?

    /// The rows, newest first. `history`: the hub's answer (nil: none, only the file's facts show); `current`: the file's text now;
    /// `names`: what to call each list file ("Inbox", a workstream's name); `today`: the app day.
    public func rows(id: String, path: String, added: String?, done: Bool, doneOn: String?, history: JSONValue?, current: String?,
                     names: [String: String], today: String) -> [Row] {
        var a: [(String, JSONValue)] = [
            ("id", .string(id)), ("path", .string(path)),
            ("task", .object([("added", added.map(JSONValue.string) ?? .null), ("done", .bool(done)), ("doneOn", doneOn.map(JSONValue.string) ?? .null)])),
            ("versions", history?["versions"] ?? .array([])), ("trail", history?["trail"] ?? .array([])),
            ("names", .object(names.sorted { $0.key < $1.key }.map { ($0.key, .string($0.value)) })),
            ("today", .string(today)),
        ]
        if let current { a.append(("current", .string(current))) }
        guard let out = call(JSONValue.object(a).text), let list = out["rows"]?.array else { return TaskActivity.facts(added: added, done: done, doneOn: doneOn) }
        return list.compactMap { r in
            guard let text = r["text"]?.string else { return nil }
            return Row(at: r["at"]?.string, date: r["date"]?.string, text: text, who: r["who"]?.string)
        }
    }

    /// Without the laptop's code (no JavaScriptCore): only what the file says.
    static func facts(added: String?, done: Bool, doneOn: String?) -> [Row] {
        var out: [Row] = []
        if done, let d = doneOn { out.append(Row(at: d, date: d, text: "Ticked off", who: nil)) }
        if let a = added.map({ String($0.prefix(10)) }) { out.append(Row(at: a, date: a, text: "Added", who: nil)) }
        return out
    }

    private func call(_ json: String) -> JSONValue? {
        lock.lock(); defer { lock.unlock() }
        #if canImport(JavaScriptCore)
        guard let core = load(), let fn = core.objectForKeyedSubscript("activity"), let r = fn.call(withArguments: [json]), r.isString,
              let text = r.toString(), let v = try? JSONValue.parse(text) else { return nil }
        if v["ok"]?.bool != true { lastError = v["error"]?.string; return nil }
        return v
        #else
        return nil
        #endif
    }

    #if canImport(JavaScriptCore)
    private func load() -> JSValue? {
        if let core { return core }
        if failed { return nil }
        guard let url = Bundle.module.url(forResource: "activitycore", withExtension: "js"), let code = try? String(contentsOf: url, encoding: .utf8),
              let ctx = JSContext() else { failed = true; lastError = "activitycore.js is missing"; return nil }
        ctx.exceptionHandler = { [weak self] _, e in self?.lastError = e?.toString() }
        ctx.evaluateScript(code, withSourceURL: url)
        guard let c = ctx.objectForKeyedSubscript("NexusActivityCore"), c.isObject else { failed = true; lastError = lastError ?? "activitycore.js did not load"; return nil }
        context = ctx
        core = c
        return c
    }
    #endif
}
