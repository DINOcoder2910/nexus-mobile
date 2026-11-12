import Foundation
import Yams

// The per-device shortcuts files, `shortcuts/<device>.yaml` (format `nexus-shortcuts/1`, the Nexus repo's docs/data-format.md
// "Shortcuts"; the laptop's renderer/src/shortcuts.js). Each device writes its own file whole; the other device changes only `keys:`
// lines. The pure half lives here: reading, writing, the line edit of one shortcut's keys, key names and the conflict rules.

/// Where shortcuts work. `parent` is the scope it sits inside (`in:`), whose shortcuts it takes over while you are there.
public struct ShortcutScope: Equatable {
    public var id: String
    public var name: String
    public var parent: String?
    public init(id: String, name: String, parent: String? = nil) { self.id = id; self.name = name; self.parent = parent }
}

public enum ShortcutKind: String, Equatable {
    /// Pressed (the default).
    case key
    /// Held down (the laptop's tutor and dictation keys).
    case hold
    /// An iPad gesture: `keys` holds gesture names ("Two-finger tap", "Pencil double-tap").
    case gesture
}

public struct Shortcut: Equatable, Identifiable {
    public var id: String
    public var name: String
    public var group: String
    public var scope: String
    public var kind: ShortcutKind
    /// 0..n bindings; [] = off.
    public var keys: [String]
    public var defaults: [String]

    public init(id: String, name: String, group: String, scope: String, kind: ShortcutKind = .key, keys: [String]? = nil, defaults: [String]) {
        self.id = id; self.name = name; self.group = group; self.scope = scope; self.kind = kind
        self.keys = keys ?? defaults
        self.defaults = defaults
    }

    /// Changed from its default (the screen shows a reset button).
    public var isOverridden: Bool { keys != defaults }
}

public struct ShortcutFile: Equatable {
    public var format: String
    public var device: String
    public var scopes: [ShortcutScope]
    public var shortcuts: [Shortcut]

    public init(device: String, scopes: [ShortcutScope], shortcuts: [Shortcut], format: String = ShortcutsYaml.format) {
        self.format = format; self.device = device; self.scopes = scopes; self.shortcuts = shortcuts
    }

    public subscript(id: String) -> Shortcut? { shortcuts.first { $0.id == id } }
    public func scope(_ id: String) -> ShortcutScope? { scopes.first { $0.id == id } }
    public func scopeName(_ id: String) -> String { scope(id)?.name ?? id }

    /// The scopes a scope sits inside, nearest first (`note` -> [`app`]).
    public func ancestors(of id: String) -> [String] {
        var out: [String] = []
        var at = scope(id)?.parent
        while let p = at, !out.contains(p), p != id {
            out.append(p)
            at = scope(p)?.parent
        }
        return out
    }

    /// The groups in the order their first shortcut comes.
    public var groups: [String] {
        var out: [String] = []
        for s in shortcuts where !out.contains(s.group) { out.append(s.group) }
        return out
    }

    public mutating func setKeys(_ id: String, _ keys: [String]) {
        if let i = shortcuts.firstIndex(where: { $0.id == id }) { shortcuts[i].keys = keys }
    }

    /// The owner's file from its own list (`registry`, keys = defaults) and what the file said before: a shortcut keeps its keys,
    /// unless they were the old default and the default changed (then it follows the new one). Ids the owner no longer has are dropped.
    public static func merged(device: String, scopes: [ShortcutScope], registry: [Shortcut], existing: ShortcutFile?) -> ShortcutFile {
        let out = registry.map { def -> Shortcut in
            var s = def
            s.keys = def.defaults
            if let e = existing?[def.id] {
                let followsDefault = e.keys == e.defaults && e.defaults != def.defaults
                if !followsDefault { s.keys = e.keys }
            }
            return s
        }
        return ShortcutFile(device: device, scopes: scopes, shortcuts: out)
    }
}

// MARK: - reading and writing

public enum ShortcutsYaml {
    public static let format = "nexus-shortcuts/1"

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case yaml(String)
        case shape(String)
        case newer(String)
        case notFound(String)
        case wouldBreak(String)
        public var description: String {
            switch self {
            case .yaml(let m): return "doesn't parse: \(m)"
            case .shape(let m): return m
            case .newer(let f): return "was written by a newer Nexus (\(f))"
            case .notFound(let id): return "has no shortcut \(id)"
            case .wouldBreak(let m): return "that edit would break the file (\(m)), so it was not saved"
            }
        }
    }

    // MARK: reading

    public static func parse(_ text: String) throws -> ShortcutFile {
        let node: Node?
        do { node = try Yams.compose(yaml: text) } catch { throw Failure.yaml(TaskFile.yamlMessage(error)) }
        guard let map = node?.mapping else { throw Failure.shape("is not a shortcuts file") }
        guard let fmt = TaskFile.string(TaskFile.value(map, "format")), fmt.hasPrefix("nexus-shortcuts/") else {
            throw Failure.shape("is not a shortcuts file (no format: nexus-shortcuts/1)")
        }
        let version = Int(fmt.dropFirst("nexus-shortcuts/".count)) ?? 0
        if version > 1 { throw Failure.newer(fmt) }
        if version < 1 { throw Failure.shape("has an unknown format (\(fmt))") }
        let device = TaskFile.string(TaskFile.value(map, "device")) ?? ""
        var scopes: [ShortcutScope] = []
        for item in TaskFile.value(map, "scopes")?.sequence.map({ Array($0) }) ?? [] {
            guard let m = item.mapping, let id = TaskFile.string(TaskFile.value(m, "id")), !id.isEmpty else { continue }
            scopes.append(ShortcutScope(id: id, name: TaskFile.string(TaskFile.value(m, "name")) ?? id, parent: TaskFile.string(TaskFile.value(m, "in"))))
        }
        var shortcuts: [Shortcut] = []
        let list = TaskFile.value(map, "shortcuts")
        if let list, list.sequence == nil, !(TaskFile.string(list) ?? "").isEmpty { throw Failure.shape("shortcuts: is not a list") }
        for item in list?.sequence.map({ Array($0) }) ?? [] {
            guard let m = item.mapping, let id = TaskFile.string(TaskFile.value(m, "id")), !id.isEmpty else { continue }
            let kind = ShortcutKind(rawValue: TaskFile.string(TaskFile.value(m, "kind")) ?? "key") ?? .key
            // no `keys:` at all means the default
            let keysNode = TaskFile.value(m, "keys")
            shortcuts.append(Shortcut(id: id, name: TaskFile.string(TaskFile.value(m, "name")) ?? id,
                                      group: TaskFile.string(TaskFile.value(m, "group")) ?? "Other",
                                      scope: TaskFile.string(TaskFile.value(m, "scope")) ?? "app", kind: kind,
                                      keys: keysNode == nil ? nil : keyList(keysNode), defaults: keyList(TaskFile.value(m, "default"))))
        }
        return ShortcutFile(device: device, scopes: scopes, shortcuts: shortcuts, format: fmt)
    }

    /// A `keys:` value: a list of strings, one string, or nothing.
    static func keyList(_ n: Node?) -> [String] {
        guard let n else { return [] }
        if let seq = n.sequence { return seq.compactMap { TaskFile.string($0) }.filter { !$0.isEmpty } }
        if let s = TaskFile.string(n), !s.isEmpty { return [s] }
        return []
    }

    // MARK: writing

    /// The whole file, as the owner writes it: scopes as flow maps, each shortcut in block style, `keys:` and `default:` as one-line
    /// JSON-style lists.
    public static func write(_ f: ShortcutFile, header: String? = nil) -> String {
        var out: [String] = []
        let deviceName = f.device == "ipad" ? "iPad" : f.device
        let comment = header ?? "Nexus's shortcuts on the \(deviceName). Change them in Settings › Shortcuts (on the iPad or the laptop), or edit `keys` here."
        out.append("# " + comment)
        out.append("format: \(format)")
        out.append("device: \(YamlEdit.scalar(f.device))")
        if f.scopes.isEmpty { out.append("scopes: []") } else {
            out.append("scopes:")
            for s in f.scopes {
                var parts = ["id: \(flowScalar(s.id))", "name: \(flowScalar(s.name))"]
                if let p = s.parent { parts.append("in: \(flowScalar(p))") }
                out.append("  - { " + parts.joined(separator: ", ") + " }")
            }
        }
        if f.shortcuts.isEmpty { out.append("shortcuts: []") } else {
            out.append("shortcuts:")
            for s in f.shortcuts {
                out.append("  - id: \(YamlEdit.scalar(s.id))")
                out.append("    name: \(YamlEdit.scalar(s.name))")
                out.append("    group: \(YamlEdit.scalar(s.group))")
                out.append("    scope: \(YamlEdit.scalar(s.scope))")
                if s.kind != .key { out.append("    kind: \(s.kind.rawValue)") }
                out.append("    keys: \(json(s.keys))")
                out.append("    default: \(json(s.defaults))")
            }
        }
        return out.joined(separator: "\n") + "\n"
    }

    /// `["Cmd+1", "Cmd+Shift+Z"]`: double-quoted, JSON escapes (a YAML double-quoted string reads them the same).
    public static func json(_ keys: [String]) -> String {
        "[" + keys.map(quote).joined(separator: ", ") + "]"
    }

    static func quote(_ s: String) -> String {
        var out = "\""
        for c in s.unicodeScalars {
            switch c {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            default:
                if c.value < 0x20 { out += String(format: "\\u%04x", c.value) } else { out.unicodeScalars.append(c) }
            }
        }
        return out + "\""
    }

    /// A scalar inside a flow map: plain when it is safe there, else double-quoted.
    static func flowScalar(_ s: String) -> String {
        let plain = YamlEdit.scalar(s)
        if plain.hasPrefix("'") || s.contains(where: { ",[]{}#:\"".contains($0) }) { return quote(s) }
        return plain
    }

    // MARK: the other device's edit: one `keys:` line

    /// Changes only the `keys:` of shortcut `id` (block style or a one-line flow map), keeping every other line as it was. The result is
    /// parsed and checked (that shortcut has the new keys, every other shortcut is unchanged) before it is returned.
    public static func setKeys(_ text: String, id: String, keys: [String]) throws -> String {
        let before = try parse(text)
        guard before[id] != nil else { throw Failure.notFound(id) }
        var (lines, trailing) = YamlEdit.split(text)
        let value = json(keys)
        if let b = YamlEdit.find(lines, id: id) {
            let pad = String(repeating: " ", count: b.fieldIndent)
            if let k = b.keys.first(where: { $0.name == "keys" }) {
                let prefix = k.start == b.item ? String(lines[b.item].prefix(b.fieldIndent)) : pad
                let line = lines[k.start]
                let rest = line.dropFirst(b.fieldIndent).dropFirst("keys:".count)
                var tail = ""
                if k.end == k.start + 1, let close = flowEnd(rest) {
                    // keep a comment after the list
                    tail = String(rest[close...])
                }
                lines.replaceSubrange(k.start..<k.end, with: [prefix + "keys: " + value + tail])
            } else {
                let at = b.keys.first(where: { $0.name == "default" })?.start ?? (b.keys.last?.end ?? b.end)
                if at == b.item {
                    let dashPrefix = String(lines[b.item].prefix(b.fieldIndent))
                    lines[b.item] = pad + lines[b.item].dropFirst(b.fieldIndent)
                    lines.insert(dashPrefix + "keys: " + value, at: b.item)
                } else {
                    lines.insert(pad + "keys: " + value, at: at)
                }
            }
        } else if let n = flowLine(lines, id: id) {
            lines[n] = try setFlowKeys(lines[n], value: value)
        } else {
            throw Failure.wouldBreak("couldn't find the line of \(id)")
        }
        let result = YamlEdit.join(lines, trailing)
        let after: ShortcutFile
        do { after = try parse(result) } catch { throw Failure.wouldBreak("\(error)") }
        guard after[id]?.keys == keys else { throw Failure.wouldBreak("the keys didn't come out as asked") }
        var expected = before
        expected.setKeys(id, keys)
        guard after == expected else { throw Failure.wouldBreak("another shortcut would change") }
        return result
    }

    /// For text starting at a flow list ("  [\"Ctrl+O\"]  # x"): the index just after its closing bracket.
    static func flowEnd(_ s: Substring) -> Substring.Index? {
        var i = s.startIndex
        while i < s.endIndex, s[i] == " " { i = s.index(after: i) }
        guard i < s.endIndex, s[i] == "[" else { return nil }
        var depth = 0
        var quote: Character?
        while i < s.endIndex {
            let c = s[i]
            if let q = quote {
                if c == "\\" && q == "\"" { i = s.index(after: i); if i < s.endIndex { i = s.index(after: i) }; continue }
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == "[" {
                depth += 1
            } else if c == "]" {
                depth -= 1
                if depth == 0 { return s.index(after: i) }
            }
            i = s.index(after: i)
        }
        return nil
    }

    /// The line of a one-line flow map item `- { id: x, ... }`.
    static func flowLine(_ lines: [String], id: String) -> Int? {
        for (n, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("- {") || t.hasPrefix("-  {") else { continue }
            guard let entries = flowEntries(line) else { continue }
            if entries.contains(where: { $0.key == "id" && YamlEdit.unquote($0.value) == id }) { return n }
        }
        return nil
    }

    struct FlowEntry { var key: String; var value: String; var range: Range<String.Index> }

    /// The entries of a one-line flow map: key, raw value, and the value's range in the line.
    static func flowEntries(_ line: String) -> [FlowEntry]? {
        guard let open = line.firstIndex(of: "{") else { return nil }
        var out: [FlowEntry] = []
        var i = line.index(after: open)
        var start = i
        var depth = 0
        var quote: Character?
        func add(_ end: String.Index) {
            let part = line[start..<end]
            guard let colon = colonIndex(part) else { return }
            let key = part[..<colon].trimmingCharacters(in: .whitespaces)
            var vs = part.index(after: colon)
            while vs < end, line[vs] == " " { vs = line.index(after: vs) }
            var ve = end
            while ve > vs, line[line.index(before: ve)] == " " { ve = line.index(before: ve) }
            out.append(FlowEntry(key: YamlEdit.unquote(key), value: String(line[vs..<ve]), range: vs..<ve))
        }
        while i < line.endIndex {
            let c = line[i]
            if let q = quote {
                if c == "\\" && q == "\"" { i = line.index(after: i); if i < line.endIndex { i = line.index(after: i) }; continue }
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == "[" || c == "{" {
                depth += 1
            } else if c == "]" {
                depth -= 1
            } else if c == "}" {
                if depth == 0 { add(i); return out }
                depth -= 1
            } else if c == "," && depth == 0 {
                add(i)
                start = line.index(after: i)
            }
            i = line.index(after: i)
        }
        return nil
    }

    /// The first `:` of a flow entry that is outside quotes.
    static func colonIndex(_ s: Substring) -> Substring.Index? {
        var quote: Character?
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if let q = quote { if c == q { quote = nil } } else if c == "\"" || c == "'" { quote = c } else if c == ":" { return i }
            i = s.index(after: i)
        }
        return nil
    }

    static func setFlowKeys(_ line: String, value: String) throws -> String {
        guard let entries = flowEntries(line) else { throw Failure.wouldBreak("a shortcut's line isn't one flow map") }
        var out = line
        if let k = entries.first(where: { $0.key == "keys" }) {
            out.replaceSubrange(k.range, with: value)
        } else if let d = entries.first(where: { $0.key == "default" }) {
            // put it before `default:` (the entry's key starts after the comma before it)
            let keyStart = line[..<d.range.lowerBound].range(of: "default", options: .backwards)!.lowerBound
            out.replaceSubrange(keyStart..<keyStart, with: "keys: \(value), ")
        } else if let close = line.lastIndex(of: "}") {
            var at = close
            while at > line.startIndex, line[line.index(before: at)] == " " { at = line.index(before: at) }
            out.replaceSubrange(at..<at, with: ", keys: \(value)")
        }
        return out
    }
}

// MARK: - key names

/// Bindings are `+`-joined, modifiers first (`Ctrl Alt Shift Win` on the laptop, `Cmd Ctrl Alt Shift` on the iPad), then one key; two
/// steps are two keys with a space (`Ctrl+K Ctrl+\`).
public enum ShortcutKeys {
    public static let iPadModifiers = ["Cmd", "Ctrl", "Alt", "Shift"]
    public static let laptopModifiers = ["Ctrl", "Alt", "Shift", "Win"]

    public static func modifiers(device: String) -> [String] { device == "ipad" ? iPadModifiers : laptopModifiers }

    /// Named keys, as the files write them.
    public static let named = ["Enter", "Esc", "Tab", "Space", "Delete", "Backspace", "Up", "Down", "Left", "Right",
                               "PageUp", "PageDown", "Home", "End", "PrintScreen"] + (1...12).map { "F\($0)" }

    /// Symbols that stand for themselves (typed without Shift).
    public static let symbols = ["/", "\\", ",", ".", "=", "-", "`", "'", "[", "]", ";"]

    static let modifierAliases: [String: String] = [
        "cmd": "Cmd", "command": "Cmd", "⌘": "Cmd",
        "ctrl": "Ctrl", "control": "Ctrl", "ctl": "Ctrl", "⌃": "Ctrl",
        "alt": "Alt", "option": "Alt", "opt": "Alt", "⌥": "Alt",
        "shift": "Shift", "⇧": "Shift",
        "win": "Win", "windows": "Win", "super": "Win", "meta": "Win",
        "globe": "Globe", "fn": "Globe", "🌐": "Globe",
    ]

    static let keyAliases: [String: String] = [
        "enter": "Enter", "return": "Enter", "↩": "Enter", "esc": "Esc", "escape": "Esc", "⎋": "Esc", "tab": "Tab", "⇥": "Tab",
        "space": "Space", "spacebar": "Space", "delete": "Delete", "del": "Delete", "⌦": "Delete", "backspace": "Backspace", "⌫": "Backspace",
        "up": "Up", "arrowup": "Up", "↑": "Up", "down": "Down", "arrowdown": "Down", "↓": "Down",
        "left": "Left", "arrowleft": "Left", "←": "Left", "right": "Right", "arrowright": "Right", "→": "Right",
        "pageup": "PageUp", "pgup": "PageUp", "pagedown": "PageDown", "pgdn": "PageDown", "home": "Home", "end": "End",
        "printscreen": "PrintScreen", "prtsc": "PrintScreen", "print": "PrintScreen", "plus": "=", "minus": "-",
    ]

    /// One step split into its modifiers (in the device's order, known names) and its key (nil for a modifiers-only hold key).
    public static func parts(_ step: String, device: String) -> (mods: [String], key: String?) {
        let raw = step.trimmingCharacters(in: .whitespaces)
        var pieces = raw.split(separator: "+", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        // "Ctrl++" : the key is "+"
        if raw.hasSuffix("++") { pieces.removeLast(2); pieces.append("+") }
        var mods = Set<String>()
        var key: String?
        let last = pieces.count - 1
        let allMods = isModifierOnly(pieces)
        for (i, p) in pieces.enumerated() where !p.isEmpty {
            if let m = modifierAliases[p.lowercased()], i < last || allMods {
                mods.insert(device != "ipad" && m == "Cmd" ? "Ctrl" : m)
            } else {
                key = keyName(p)
            }
        }
        let order = modifiers(device: device) + ["Globe"]
        let sorted = order.filter { mods.contains($0) } + mods.subtracting(order).sorted()
        return (sorted, key)
    }

    static func isModifierOnly(_ pieces: [String]) -> Bool {
        pieces.allSatisfy { $0.isEmpty || modifierAliases[$0.lowercased()] != nil }
    }

    static func keyName(_ p: String) -> String {
        if let k = keyAliases[p.lowercased()] { return k }
        if p.count == 1 { return p.uppercased() }
        let l = p.lowercased()
        if l.hasPrefix("f"), let n = Int(l.dropFirst()), n >= 1, n <= 24 { return "F\(n)" }
        return p.prefix(1).uppercased() + p.dropFirst()
    }

    /// A binding in the file's form: modifiers in the device's order, the key's name as the files write it.
    public static func normalize(_ binding: String, device: String) -> String {
        binding.split(separator: " ").map { step -> String in
            let p = parts(String(step), device: device)
            return (p.mods + (p.key.map { [$0] } ?? [])).joined(separator: "+")
        }.joined(separator: " ")
    }

    /// A binding made from pressed modifiers and a key.
    public static func make(mods: Set<String>, key: String?, device: String) -> String {
        let order = modifiers(device: device)
        return (order.filter { mods.contains($0) } + (key.map { [$0] } ?? [])).joined(separator: "+")
    }

    static let iPadSymbols: [String: String] = ["Cmd": "⌘", "Ctrl": "⌃", "Alt": "⌥", "Shift": "⇧", "Globe": "🌐"]
    static let iPadKeySymbols: [String: String] = [
        "Enter": "↩", "Esc": "esc", "Tab": "⇥", "Space": "Space", "Delete": "⌦", "Backspace": "⌫",
        "Up": "↑", "Down": "↓", "Left": "←", "Right": "→", "PageUp": "⇞", "PageDown": "⇟", "Home": "↖", "End": "↘",
    ]

    /// How a key chip shows a binding: Apple's symbols on the iPad (⌃⌥⇧⌘ order, as iPadOS shows them), the file's text on the laptop.
    public static func display(_ binding: String, device: String, kind: ShortcutKind = .key) -> String {
        if kind == .gesture { return binding }
        guard device == "ipad" else { return normalize(binding, device: device) }
        return binding.split(separator: " ").map { step -> String in
            let p = parts(String(step), device: device)
            let mods = ["Globe", "Ctrl", "Alt", "Shift", "Cmd"].filter { p.mods.contains($0) }.compactMap { iPadSymbols[$0] }.joined()
            let key = p.key.map { iPadKeySymbols[$0] ?? $0 } ?? ""
            return mods + key
        }.joined(separator: " ")
    }
}

// MARK: - conflicts

public struct ShortcutIssue: Equatable {
    public enum Kind: Equatable {
        /// The same binding twice in one scope (red on both rows).
        case conflict
        /// The device keeps this binding for itself (iPadOS, or Windows for a `system` shortcut).
        case reserved
        /// This shortcut's scope sits inside the other's: here this one wins (a note, not an error).
        case takesOver
        /// The other shortcut's scope sits inside this one's: there the other wins.
        case takenOver
        /// A `system` shortcut has the same binding and gets it first.
        case shadowed
    }
    public var kind: Kind
    public var binding: String
    /// The other shortcut's id.
    public var other: String?
    /// For takesOver / takenOver: the inner scope, where the inner shortcut wins.
    public var scope: String?

    public var isError: Bool { kind == .conflict || kind == .reserved }
}

public enum ShortcutConflicts {
    /// Keys iPadOS keeps for itself (any combination with the Globe key too).
    public static let iPadReserved = ["Cmd+Tab", "Cmd+Shift+Tab", "Cmd+Space", "Cmd+H", "Cmd+Alt+D", "Cmd+Shift+3", "Cmd+Shift+4",
                                      "Cmd+Shift+5", "Ctrl+Space"]
    /// Keys Windows keeps for itself (checked for `system` shortcuts).
    public static let windowsReserved = ["Win+L", "Win+D", "Win+Tab", "Win+Shift+S", "Alt+Tab", "Alt+F4", "Ctrl+Alt+Delete", "Ctrl+Shift+Esc",
                                         "Win+E", "Win+R", "Win+I", "Win+V", "Win+.", "Win+PrintScreen", "PrintScreen"]

    /// True when the device keeps this binding for itself.
    public static func isReserved(_ binding: String, device: String) -> Bool {
        let b = ShortcutKeys.normalize(binding, device: device)
        if device == "ipad" {
            if b.split(separator: "+").contains("Globe") { return true }
            return iPadReserved.map { ShortcutKeys.normalize($0, device: device) }.contains(b)
        }
        return windowsReserved.map { ShortcutKeys.normalize($0, device: device) }.contains(b)
    }

    /// Whether the reserved keys apply to a shortcut in this scope: always on the iPad (iPadOS takes them first everywhere), only for
    /// `system` shortcuts on the laptop.
    static func reservedApplies(device: String, scope: String) -> Bool { device == "ipad" || scope == "system" }

    /// The form two bindings are compared in.
    static func key(_ binding: String, kind: ShortcutKind, device: String) -> String {
        kind == .gesture ? binding.trimmingCharacters(in: .whitespaces).lowercased() : ShortcutKeys.normalize(binding, device: device)
    }

    static func sameClass(_ a: ShortcutKind, _ b: ShortcutKind) -> Bool { (a == .gesture) == (b == .gesture) }

    /// Every shortcut's issues, by id (shortcuts without any are left out).
    public static func compute(_ f: ShortcutFile) -> [String: [ShortcutIssue]] {
        var out: [String: [ShortcutIssue]] = [:]
        func add(_ id: String, _ issue: ShortcutIssue) {
            if !(out[id]?.contains(issue) ?? false) { out[id, default: []].append(issue) }
        }
        let list = f.shortcuts
        for s in list where s.kind != .gesture && reservedApplies(device: f.device, scope: s.scope) {
            for b in s.keys where isReserved(b, device: f.device) { add(s.id, ShortcutIssue(kind: .reserved, binding: b)) }
        }
        for i in list.indices {
            for j in list.indices where j > i {
                let s = list[i], t = list[j]
                guard sameClass(s.kind, t.kind) else { continue }
                for b in s.keys {
                    let kb = key(b, kind: s.kind, device: f.device)
                    guard !kb.isEmpty, t.keys.contains(where: { key($0, kind: t.kind, device: f.device) == kb }) else { continue }
                    if s.scope == t.scope {
                        add(s.id, ShortcutIssue(kind: .conflict, binding: b, other: t.id))
                        add(t.id, ShortcutIssue(kind: .conflict, binding: b, other: s.id))
                    } else if f.ancestors(of: s.scope).contains(t.scope) {
                        add(s.id, ShortcutIssue(kind: .takesOver, binding: b, other: t.id, scope: s.scope))
                        add(t.id, ShortcutIssue(kind: .takenOver, binding: b, other: s.id, scope: s.scope))
                    } else if f.ancestors(of: t.scope).contains(s.scope) {
                        add(t.id, ShortcutIssue(kind: .takesOver, binding: b, other: s.id, scope: t.scope))
                        add(s.id, ShortcutIssue(kind: .takenOver, binding: b, other: t.id, scope: t.scope))
                    } else if s.scope == "system" {
                        add(t.id, ShortcutIssue(kind: .shadowed, binding: b, other: s.id))
                    } else if t.scope == "system" {
                        add(s.id, ShortcutIssue(kind: .shadowed, binding: b, other: t.id))
                    }
                    // scopes side by side never clash
                }
            }
        }
        return out
    }

    /// How many shortcuts have a conflict (red).
    public static func errorCount(_ issues: [String: [ShortcutIssue]]) -> Int {
        issues.values.filter { $0.contains(where: \.isError) }.count
    }

    /// The shortcuts (other than `except`) that already use `binding` in this very scope: the ones the screen offers to swap with or
    /// take the key from.
    public static func holders(_ f: ShortcutFile, binding: String, scope: String, kind: ShortcutKind, except: String) -> [Shortcut] {
        let kb = key(binding, kind: kind, device: f.device)
        return f.shortcuts.filter { t in
            t.id != except && t.scope == scope && sameClass(kind, t.kind)
                && t.keys.contains { key($0, kind: t.kind, device: f.device) == kb }
        }
    }

    /// The binding taken from `from` and given to `to`, replacing `old` there (nil: added). With `swap`, `from` gets `old` back in its place.
    public static func move(_ f: inout ShortcutFile, binding: String, to: String, replacing old: String?, from: [String], swap: Bool) {
        let device = f.device
        func kb(_ k: String, _ kind: ShortcutKind) -> String { key(k, kind: kind, device: device) }
        for id in from {
            guard let t = f[id] else { continue }
            var keys: [String] = []
            for k in t.keys {
                if kb(k, t.kind) == kb(binding, t.kind) {
                    if swap, let old, !keys.contains(old) { keys.append(old) }
                } else { keys.append(k) }
            }
            f.setKeys(id, keys)
        }
        if let s = f[to] {
            var keys = s.keys
            if let old, let i = keys.firstIndex(of: old) { keys[i] = binding } else if !keys.contains(binding) { keys.append(binding) }
            f.setKeys(to, keys)
        }
    }
}
