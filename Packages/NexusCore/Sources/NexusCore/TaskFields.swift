import Foundation

// The fields the iPad and iPhone could only show until now: waiting on, repeats, tags and the note. Written as the laptop
// writes them (docs/data-format.md "Fields"): `waiting: {on: Ms Settle, since: 2026-10-01}`, `every: {freq: week, on: fri}`,
// `tags: [summative, lab]`, `note: |` with the text indented under it.

extension YamlEdit {
    /// A string inside a flow map or list, quoted when a comma, bracket or brace would end it early.
    public static func flowScalar(_ s: String) -> String {
        let t = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        if t.contains(where: { ",[]{}".contains($0) }) && !scalar(t).hasPrefix("'") {
            return "'" + t.replacingOccurrences(of: "'", with: "''") + "'"
        }
        return scalar(t)
    }

    /// `{on: Ms Settle, since: 2026-10-01}` from (key, value already written as YAML) pairs.
    public static func flowMap(_ pairs: [(String, String)]) -> String {
        "{" + pairs.map { "\($0.0): \($0.1)" }.joined(separator: ", ") + "}"
    }

    /// The lines of `key: |` with `text` under it, relative to the field indent (two more spaces for the text).
    public static func blockScalar(key: String, text: String) -> [String] {
        var body = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").map { line -> String in
            var l = line
            while l.last == " " || l.last == "\t" { l.removeLast() }
            return l
        }
        while body.last == "" { body.removeLast() }
        while body.first == "" { body.removeFirst() }
        // text that starts with spaces needs the indent said outright, or YAML would take those spaces as the indent
        let first = body.first { !$0.isEmpty } ?? ""
        let head = first.hasPrefix(" ") ? "\(key): |2" : "\(key): |"
        return [head] + body.map { $0.isEmpty ? "" : "  " + $0 }
    }

    /// Sets a task's own field to one or more lines (written relative to the field indent; the first is `key: …`), or removes it.
    public static func setFieldLines(_ text: String, id: String, key: String, lines value: [String]?) throws -> String {
        guard let value, value.count > 1 else { return try setField(text, id: id, key: key, yaml: value.map { String($0[0].dropFirst(key.count + 2)) }) }
        var (lines, trailing) = split(text)
        guard let b = find(lines, id: id) else { throw Failure.notFound(id) }
        let pad = String(repeating: " ", count: b.fieldIndent)
        let dashPrefix = String(lines[b.item].prefix(b.fieldIndent))
        if let k = b.keys.first(where: { $0.name == key }) {
            let padded = value.enumerated().map { i, l -> String in
                if i == 0 { return (k.start == b.item ? dashPrefix : pad) + l }
                return l.isEmpty ? "" : pad + l
            }
            lines.replaceSubrange(k.start..<k.end, with: padded)
        } else {
            let at = b.keys.first(where: { rank($0.name) > rank(key) })?.start ?? (b.keys.last?.end ?? b.end)
            lines = insertField(lines, b, key: key, valueLines: value)
            // insertField pads every line it adds, blank ones too: keep the note's blank lines empty
            for i in at..<min(lines.count, at + value.count) where value[i - at].isEmpty { lines[i] = "" }
        }
        return join(lines, trailing)
    }
}

extension TaskEditor {
    /// Waiting on someone (since a day, today by default), or not waiting any more (`who` nil or empty).
    public func setWaiting(_ t: NexusTask, on who: String?, since: String?, in s: Snapshot) throws -> Change {
        let w = who?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if w.isEmpty { return try field(t, "waiting", nil, in: s, message: "Not waiting: \(t.text)") }
        var pairs = [("on", YamlEdit.flowScalar(w))]
        if let since, Days.isIso(since) { pairs.append(("since", since)) }
        return try field(t, "waiting", YamlEdit.flowMap(pairs), in: s, message: "Waiting on \(w): \(t.text)")
    }

    /// Repeats (`day`, `weekdays`, `week` with an optional weekday, each with an optional `until`), or not (nil).
    public func setRepeat(_ t: NexusTask, _ r: Repeat?, in s: Snapshot) throws -> Change {
        guard let r else { return try field(t, "every", nil, in: s, message: "Doesn't repeat: \(t.text)") }
        var pairs = [("freq", YamlEdit.flowScalar(r.freq))]
        let on = r.on.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        if on.count == 1 { pairs.append(("on", YamlEdit.flowScalar(on[0]))) }
        if on.count > 1 { pairs.append(("on", YamlEdit.flow(on))) }
        if let u = r.until, Days.isIso(u) { pairs.append(("until", u)) }
        return try field(t, "every", YamlEdit.flowMap(pairs), in: s, message: "Repeats: \(t.text)")
    }

    /// The task's tags (without #), in the order given, each once; none removes the field.
    public func setTags(_ t: NexusTask, _ tags: [String], in s: Snapshot) throws -> Change {
        var seen = Set<String>()
        let clean = tags.map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        return try field(t, "tags", clean.isEmpty ? nil : YamlEdit.flow(clean.map { YamlEdit.flowScalar($0) }), in: s,
                         message: clean.isEmpty ? "No tags: \(t.text)" : "Tags: \(t.text)")
    }

    /// The task's note, a block of text under `note: |`; empty removes it.
    public func setNote(_ t: NexusTask, _ note: String?, in s: Snapshot) throws -> Change {
        let text = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return try edit(t, in: s, message: text.isEmpty ? "No note: \(t.text)" : "Note: \(t.text)") {
            try YamlEdit.setFieldLines($0, id: t.id, key: "note", lines: text.isEmpty ? nil : YamlEdit.blockScalar(key: "note", text: note ?? ""))
        }
    }
}
