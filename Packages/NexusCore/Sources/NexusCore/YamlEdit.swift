import Foundation

/// Line-level edits on a task file, the same contract as the laptop's `container.js` + `yamlpatch.js`: an edit changes only the lines
/// it must, so comments, order and formatting survive, and the laptop sees a one-line diff. Every edit is checked by parsing the result
/// (`TaskEditor`), and a file that would not parse is never written.
public enum YamlEdit {
    public enum Failure: Error, CustomStringConvertible {
        case notFound(String)
        case badFile(String)
        public var description: String {
            switch self {
            case .notFound(let id): return "Task \(id) is not in the file any more"
            case .badFile(let m): return m
            }
        }
    }

    /// The order the laptop writes a task's fields in. Keys the user added go last.
    public static let fieldOrder = ["id", "title", "done", "due", "key", "plan", "est", "waiting", "every", "someday", "tags", "email", "note", "added", "subtasks"]
    static func rank(_ key: String) -> Int { fieldOrder.firstIndex(of: key) ?? 100 }

    struct Key { var name: String; var start: Int; var end: Int }
    struct Block {
        var item: Int          // the "- " line
        var dashIndent: Int
        var fieldIndent: Int
        var end: Int           // exclusive, trailing blank lines left out
        var keys: [Key]
    }

    // MARK: lines

    static func split(_ text: String) -> (lines: [String], trailingNewline: Bool) {
        var lines = text.components(separatedBy: "\n")
        let trailing = text.hasSuffix("\n")
        if trailing { lines.removeLast() }
        return (lines.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }, trailing)
    }

    static func join(_ lines: [String], _ trailing: Bool) -> String {
        lines.joined(separator: "\n") + (trailing || lines.isEmpty ? "\n" : "")
    }

    static func indent(_ line: String) -> Int { line.prefix { $0 == " " }.count }
    static func isBlank(_ line: String) -> Bool { line.trimmingCharacters(in: .whitespaces).isEmpty }
    static func isComment(_ line: String) -> Bool { line.trimmingCharacters(in: .whitespaces).hasPrefix("#") }

    /// The key at the start of `s` ("title: x" -> "title"), or nil.
    static func keyName(_ s: Substring) -> String? {
        var name = ""
        for c in s {
            if c == ":" { return name.isEmpty ? nil : name }
            if c.isLetter || c.isNumber || c == "_" || c == "-" { name.append(c) } else { return nil }
        }
        return nil
    }

    /// For a "- key: value" line: (dash indent, field indent). nil when the line is not a list item.
    static func dash(_ line: String) -> (Int, Int)? {
        let i = indent(line)
        let rest = line.dropFirst(i)
        guard rest.hasPrefix("-"), rest.count >= 2 else { return nil }
        let after = rest.dropFirst()
        guard after.first == " " else { return nil }
        let spaces = after.prefix { $0 == " " }.count
        return (i, i + 1 + spaces)
    }

    static func unquote(_ s: String) -> String {
        var v = s.trimmingCharacters(in: .whitespaces)
        if let hash = v.range(of: " #") { v = String(v[..<hash.lowerBound]).trimmingCharacters(in: .whitespaces) }
        if v.count >= 2, (v.hasPrefix("'") && v.hasSuffix("'")) || (v.hasPrefix("\"") && v.hasSuffix("\"")) { v = String(v.dropFirst().dropLast()) }
        return v
    }

    /// Finds the task with this id.
    static func find(_ lines: [String], id: String) -> Block? {
        for (n, line) in lines.enumerated() {
            let i = indent(line)
            var rest = line.dropFirst(i)
            var item = n, dashIndent = -1, fieldIndent = i
            if let d = dash(line) {
                dashIndent = d.0; fieldIndent = d.1
                rest = line.dropFirst(d.1)
            }
            guard keyName(rest) == "id" else { continue }
            guard unquote(String(rest.dropFirst(3))) == id else { continue }
            if dashIndent < 0 {
                // the id is not the first key: walk up to this item's "- " line
                var m = n - 1
                var found = false
                while m >= 0 {
                    let l = lines[m]
                    if !isBlank(l), !isComment(l) {
                        if let d = dash(l), d.1 == fieldIndent { item = m; dashIndent = d.0; found = true; break }
                        if indent(l) < fieldIndent { break }
                    }
                    m -= 1
                }
                if !found { continue }
            }
            return block(lines, item: item, dashIndent: dashIndent, fieldIndent: fieldIndent)
        }
        return nil
    }

    static func block(_ lines: [String], item: Int, dashIndent: Int, fieldIndent: Int) -> Block {
        var end = item + 1
        while end < lines.count {
            let l = lines[end]
            if !isBlank(l) && indent(l) < fieldIndent { break }
            end += 1
        }
        while end > item + 1, isBlank(lines[end - 1]) || (isComment(lines[end - 1]) && indent(lines[end - 1]) <= fieldIndent) { end -= 1 }
        var keys: [Key] = []
        if let k = keyName(lines[item].dropFirst(fieldIndent)) { keys.append(Key(name: k, start: item, end: item + 1)) }
        for n in (item + 1)..<max(end, item + 1) {
            let l = lines[n]
            if indent(l) == fieldIndent, !isComment(l), let k = keyName(l.dropFirst(fieldIndent)) {
                keys.append(Key(name: k, start: n, end: n + 1))
            }
        }
        for i in keys.indices {
            var e = i + 1 < keys.count ? keys[i + 1].start : end
            while e > keys[i].start + 1, isBlank(lines[e - 1]) { e -= 1 }
            keys[i].end = e
        }
        return Block(item: item, dashIndent: dashIndent, fieldIndent: fieldIndent, end: end, keys: keys)
    }

    // MARK: values

    static let reserved: Set<String> = ["true", "false", "null", "yes", "no", "on", "off", "y", "n", "~"]

    /// A string as a YAML scalar, quoted only when it must be (the laptop's "safe quoting").
    public static func scalar(_ s: String) -> String {
        let t = s.replacingOccurrences(of: "\n", with: " ")
        let needs = t.isEmpty || t != t.trimmingCharacters(in: .whitespaces) || t.contains(": ") || t.contains(" #") || t.hasSuffix(":")
            || "-?:,[]{}#&*!|>'\"%@`".contains(t.first!) || reserved.contains(t.lowercased())
            || Double(t) != nil || Days.isIso(t) || t.hasPrefix("0x")
        return needs ? "'" + t.replacingOccurrences(of: "'", with: "''") + "'" : t
    }

    /// A flow list: "[2026-10-27, 2026-10-29 14:00]"
    public static func flow(_ items: [String]) -> String {
        "[" + items.map { item in
            let special = item.contains(",") || item.contains("[") || item.contains("]") || item.contains("{") || item.contains("}") || item.contains(": ") || item.contains(" #")
            return special || item.isEmpty ? "'" + item.replacingOccurrences(of: "'", with: "''") + "'" : item
        }.joined(separator: ", ") + "]"
    }

    // MARK: edits

    /// Sets a task's own field to a value already written as YAML (a scalar, a flow list or map), or removes it (`nil`).
    public static func setField(_ text: String, id: String, key: String, yaml value: String?) throws -> String {
        var (lines, trailing) = split(text)
        guard let b = find(lines, id: id) else { throw Failure.notFound(id) }
        let pad = String(repeating: " ", count: b.fieldIndent)
        let dashPrefix = String(lines[b.item].prefix(b.fieldIndent))
        if let k = b.keys.first(where: { $0.name == key }) {
            if let value {
                let line = (k.start == b.item ? dashPrefix : pad) + "\(key): \(value)"
                lines.replaceSubrange(k.start..<k.end, with: [line])
            } else if k.start == b.item {
                // removing the first key: the next key moves up onto the "- " line
                guard let next = b.keys.dropFirst().first else { throw Failure.badFile("can't remove the only field of a task") }
                var replacement = Array(lines[next.start..<b.end])
                replacement[0] = dashPrefix + replacement[0].dropFirst(b.fieldIndent)
                lines.replaceSubrange(b.item..<b.end, with: replacement)
            } else {
                lines.removeSubrange(k.start..<k.end)
            }
        } else if let value {
            lines = insertField(lines, b, key: key, valueLines: ["\(key): \(value)"])
        }
        return join(lines, trailing)
    }

    /// Inserts a field (one or more lines, written relative to the field indent) at its place in the field order.
    static func insertField(_ lines: [String], _ b: Block, key: String, valueLines: [String]) -> [String] {
        var lines = lines
        let pad = String(repeating: " ", count: b.fieldIndent)
        let dashPrefix = String(lines[b.item].prefix(b.fieldIndent))
        let padded = valueLines.map { pad + $0 }
        if let after = b.keys.first(where: { rank($0.name) > rank(key) }) {
            if after.start == b.item {
                var first = padded
                first[0] = dashPrefix + valueLines[0]
                lines[b.item] = pad + lines[b.item].dropFirst(b.fieldIndent)
                lines.insert(contentsOf: first, at: b.item)
            } else {
                lines.insert(contentsOf: padded, at: after.start)
            }
        } else {
            let at = b.keys.last?.end ?? b.end
            lines.insert(contentsOf: padded, at: at)
        }
        return lines
    }

    /// Adds a task at the end of the file's `tasks:` list, or of `parent`'s subtasks. `fields` are (key, YAML value) after id and title.
    public static func addTask(_ text: String, id: String, title: String, fields: [(String, String)] = [], parent: String? = nil) throws -> String {
        var (lines, trailing) = split(text)
        let body = ["id: \(id)", "title: \(scalar(title))"] + fields.sorted { rank($0.0) < rank($1.0) }.map { "\($0.0): \($0.1)" }
        func item(_ dashIndent: Int) -> [String] {
            let pad = String(repeating: " ", count: dashIndent)
            return body.enumerated().map { $0.offset == 0 ? pad + "- " + $0.element : pad + "  " + $0.element }
        }
        if let parent {
            guard let b = find(lines, id: parent) else { throw Failure.notFound(parent) }
            if let k = b.keys.first(where: { $0.name == "subtasks" }) {
                let inline = lines[k.start].dropFirst(b.fieldIndent).dropFirst("subtasks:".count).trimmingCharacters(in: .whitespaces)
                if inline == "[]" || (inline.isEmpty && k.end == k.start + 1) {
                    let keyPrefix = k.start == b.item ? String(lines[b.item].prefix(b.fieldIndent)) : String(repeating: " ", count: b.fieldIndent)
                    lines.replaceSubrange(k.start..<k.end, with: [keyPrefix + "subtasks:"] + item(b.fieldIndent + 2))
                } else {
                    let childIndent = (k.start + 1..<k.end).compactMap { dash(lines[$0]) }.first?.0 ?? b.fieldIndent + 2
                    lines.insert(contentsOf: item(childIndent), at: k.end)
                }
            } else {
                let child = item(b.fieldIndent + 2).map { String($0.dropFirst(b.fieldIndent)) }
                lines = insertField(lines, b, key: "subtasks", valueLines: ["subtasks:"] + child)
            }
            return join(lines, trailing)
        }
        guard let t = lines.firstIndex(where: { $0.hasPrefix("tasks:") }) else {
            // no list yet: a fresh file
            let prefix = lines.isEmpty || lines.allSatisfy(isBlank) ? [] : lines + [""]
            return join(prefix + ["tasks:"] + item(2), true)
        }
        let inline = lines[t].dropFirst("tasks:".count).trimmingCharacters(in: .whitespaces)
        var end = t + 1
        while end < lines.count, isBlank(lines[end]) || isComment(lines[end]) || indent(lines[end]) > 0 || lines[end].hasPrefix("- ") { end += 1 }
        while end > t + 1, isBlank(lines[end - 1]) { end -= 1 }
        if inline == "[]" || (inline.isEmpty && end == t + 1) {
            lines.replaceSubrange(t..<end, with: ["tasks:"] + item(2))
        } else {
            let dashIndent = (t + 1..<end).compactMap { dash(lines[$0]) }.first?.0 ?? 2
            lines.insert(contentsOf: item(dashIndent), at: end)
        }
        return join(lines, trailing)
    }

    /// Every id used in a text (to keep new ids unique within a file even before the index knows them).
    public static func ids(_ text: String) -> Set<String> {
        var out = Set<String>()
        for line in split(text).lines {
            var rest = line.dropFirst(indent(line))
            if rest.hasPrefix("- ") { rest = rest.dropFirst(2).drop { $0 == " " } }
            if keyName(rest) == "id" { out.insert(unquote(String(rest.dropFirst(3)))) }
        }
        return out
    }
}

/// Short task ids like the laptop's (`ids.js`): 4 characters, a letter first, no look-alikes.
public enum TaskIds {
    static let first = Array("abcdefghjkmnpqrstuvwxyz")
    static let rest = Array("abcdefghjkmnpqrstuvwxyz23456789")
    static let reserved: Set<String> = ["true", "false", "null", "yes", "no", "on", "off", "none"]

    public static func new(taken: Set<String>) -> String {
        var tries = 0
        while true {
            let len = 4 + tries / 50
            var id = String(first.randomElement()!)
            for _ in 1..<len { id.append(rest.randomElement()!) }
            if !taken.contains(id) && !reserved.contains(id) { return id }
            tries += 1
        }
    }
}
