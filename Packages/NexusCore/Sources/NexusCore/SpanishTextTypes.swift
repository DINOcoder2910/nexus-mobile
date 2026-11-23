import Foundation

/// Spanish › Text types (the laptop's desktop/backend/src/texttypes.rs): a guide for each IB ab initio text type, one markdown file each
/// in `study/spanish/text-types/` of the subject's folder (the laptop writes its own the first time; then they are the user's files).
/// A guide: front matter (title, english, group, register, matches), then `## Structure` (numbered), `## Rules` (bullets),
/// `## Vocabulary` and `## Sentence stems` (### groups of `- Spanish · English [skill id]`), `## Exemplar` (`> the task`, the text,
/// `### Why it works`). Any other `##` section is kept as it is.
public enum SpanishTextTypes {
    public static let dir = Spanish.dir + "/text-types"
    /// the laptop's order of its own guides
    public static let order = ["correo-informal", "carta-informal", "blog", "diario", "postal", "redes-sociales", "invitacion",
                               "correo-formal", "carta-formal", "instrucciones", "articulo", "folleto", "anuncio", "entrevista", "resena", "discurso"]
    public static let groups: [(id: String, title: String)] = [("personal", "Personal texts"), ("professional", "Professional texts"), ("mass media", "Mass media texts"), ("other", "Your own")]

    public struct Item: Equatable, Sendable, Hashable {
        public var es: String, en: String, skill: String
        public init(es: String, en: String, skill: String) { self.es = es; self.en = en; self.skill = skill }
    }
    public struct Group: Equatable, Sendable, Hashable { public var title: String; public var items: [Item] }
    public struct Section: Equatable, Sendable, Hashable { public var title: String; public var text: String }
    public struct Guide: Equatable, Sendable, Identifiable, Hashable {
        public var id: String { slug }
        public var slug = "", title = "", english = "", group = "other", register = "", path = ""
        public var matches: [String] = []
        public var structure: [String] = [], rules: [String] = []
        public var vocab: [Group] = [], stems: [Group] = []
        public var task = "", exemplar = "", notes: [String] = []
        public var more: [Section] = []
    }

    static func bullet(_ l: String) -> String? {
        let t = l.drop { $0 == " " || $0 == "\t" }
        for p in ["- ", "* "] where t.hasPrefix(p) { return String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        return nil
    }
    static func numbered(_ l: String) -> String? {
        let t = l.drop { $0 == " " || $0 == "\t" }
        let digits = t.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let rest = t.dropFirst(digits.count)
        for p in [". ", ") "] where rest.hasPrefix(p) { return String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        return nil
    }
    /// `Spanish · English [skill.id]`: the tag only when it names a skill
    public static func item(_ line: String) -> Item {
        var t = line.trimmingCharacters(in: .whitespaces)
        var sk = ""
        if t.hasSuffix("]"), let open = t.lastIndex(of: "[") {
            let tag = t[t.index(after: open)..<t.index(before: t.endIndex)].trimmingCharacters(in: .whitespaces)
            if Spanish.isSkill(tag) { sk = tag; t = String(t[..<open]).trimmingCharacters(in: .whitespaces) }
        }
        if let r = t.range(of: " · ") { return Item(es: String(t[..<r.lowerBound]).trimmingCharacters(in: .whitespaces), en: String(t[r.upperBound...]).trimmingCharacters(in: .whitespaces), skill: sk) }
        return Item(es: t, en: "", skill: sk)
    }
    static func groups(_ body: [String]) -> [Group] {
        var out: [Group] = []
        for l in body {
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("### ") { out.append(Group(title: String(t.dropFirst(4)).trimmingCharacters(in: .whitespaces), items: [])) }
            else if let b = bullet(l) { if out.isEmpty { out.append(Group(title: "", items: [])) }; out[out.count - 1].items.append(item(b)) }
        }
        return out.filter { !$0.items.isEmpty }
    }

    /// one guide file read into its parts
    public static func parse(slug: String, text raw: String) -> Guide {
        var g = Guide()
        g.slug = slug
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        if text.hasPrefix("\u{feff}") { text.removeFirst() }
        var body = text
        if text.hasPrefix("---\n"), let end = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex) {
            let fm = (try? YValue.parse(String(text[text.index(text.startIndex, offsetBy: 4)..<end.lowerBound]))) ?? .null
            g.title = fm["title"]?.str.trimmingCharacters(in: .whitespaces) ?? ""
            g.english = fm["english"]?.str.trimmingCharacters(in: .whitespaces) ?? ""
            g.register = fm["register"]?.str.trimmingCharacters(in: .whitespaces) ?? ""
            g.matches = (fm["matches"]?.strings ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let grp = (fm["group"]?.str ?? "").lowercased().trimmingCharacters(in: .whitespaces)
            g.group = ["personal", "professional", "mass media"].contains(grp) ? grp : "other"
            let after = text[end.upperBound...]
            body = after.firstIndex(of: "\n").map { String(after[after.index(after: $0)...]) } ?? ""
        }
        if g.title.isEmpty { g.title = slug.replacingOccurrences(of: "-", with: " ") }
        let parts = ("\n" + body).components(separatedBy: "\n## ").dropFirst()
        for part in parts {
            var lines = part.components(separatedBy: "\n")
            let head = lines.removeFirst().trimmingCharacters(in: .whitespaces)
            switch head.lowercased() {
            case "structure": g.structure = lines.compactMap { numbered($0) ?? bullet($0) }
            case "rules": g.rules = lines.compactMap(bullet)
            case "vocabulary": g.vocab = groups(lines)
            case "sentence stems": g.stems = groups(lines)
            case "exemplar":
                let cut = lines.firstIndex { $0.hasPrefix("### ") }
                let main = Array(lines[..<(cut ?? lines.count)])
                let notes = cut.map { Array(lines[($0 + 1)...]) } ?? []
                var k = 0
                while k < main.count, main[k].trimmingCharacters(in: .whitespaces).isEmpty || main[k].trimmingCharacters(in: .whitespaces).hasPrefix(">") { k += 1 }
                g.task = main[..<k].compactMap { l -> String? in let t = l.trimmingCharacters(in: .whitespaces); return t.hasPrefix(">") ? String(t.dropFirst()).trimmingCharacters(in: .whitespaces) : nil }.joined(separator: " ")
                g.exemplar = main[k...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                g.notes = notes.compactMap(bullet)
            default: g.more.append(Section(title: head, text: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
        return g
    }

    /// the guides in the order the laptop lists them: its own first, then the user's by name
    public static func sorted(_ gs: [Guide]) -> [Guide] {
        gs.sorted { a, b in
            let x = order.firstIndex(of: a.slug) ?? Int.max, y = order.firstIndex(of: b.slug) ?? Int.max
            return x != y ? x < y : a.slug < b.slug
        }
    }
    static func fold(_ s: String) -> String { s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).split(separator: " ").joined(separator: " ") }
    /// the guides a prompt's text types point at (a prompt offering "correo electrónico" gets both emails)
    public static func guidesFor(_ types: [String], _ guides: [Guide]) -> [Guide] {
        let want = Set(types.map(fold))
        return guides.filter { g in g.matches.contains { want.contains(fold($0)) } }
    }
    /// a guide's conventions for the examiner, as the laptop gives them (texttypes.rs conventions)
    public static func conventions(_ g: Guide) -> String {
        var l = ["\(g.title) (\(g.english)), register: \(g.register)", "Structure:"]
        l += g.structure.map { "- " + $0.replacingOccurrences(of: "**", with: "") }
        l.append("Rules:")
        l += g.rules.map { "- " + $0.replacingOccurrences(of: "*", with: "") }
        return l.joined(separator: "\n")
    }
    /// the whole guide as text, for the tutor on the iPhone and iPad (it cannot open files): the exemplar left out unless asked for
    public static func forTutor(_ g: Guide, exemplar: Bool = false) -> String {
        var l = [conventions(g)]
        for (name, gs) in [("Sentence stems", g.stems), ("Vocabulary", g.vocab)] where !gs.isEmpty {
            l.append(name + ":")
            for x in gs { l.append("  " + x.title + ": " + x.items.map { $0.es + ($0.en.isEmpty ? "" : " (\($0.en))") + ($0.skill.isEmpty ? "" : " [\($0.skill)]") }.joined(separator: "; ")) }
        }
        if exemplar, !g.exemplar.isEmpty { l.append("Exemplar (task: \(g.task)):\n" + g.exemplar) }
        return l.joined(separator: "\n")
    }
    /// the first message of a practice chat about one text type (the guide itself goes with the chat's memory: SpanishChat.guide)
    public static func practise(_ g: Guide) -> String {
        let en = g.english.lowercased()
        let a = en.first.map { "aeiou".contains($0) } == true ? "an" : "a"
        return "I want to practise writing \(a) \(en) (\(g.title)). If one of my teacher's prompts offers this text type, use that; otherwise give me a short task like Paper 1's. Then check what I write against my guide's structure and rules."
    }
    /// the guide for the tutor's memory, under its own heading
    public static func tutorSection(_ g: Guide) -> String {
        "## The student's guide for this text type (\(dir)/\(g.slug).md; hold them to its structure and rules, keep the exemplar back unless they ask, and a stem tagged with a skill not taught yet is a set phrase)\n" + forTutor(g)
    }
    /// the guide a message talks about (the first whose `matches` it names as whole words), so a chat that starts "help me with my blog" gets the blog's guide
    public static func mentioned(_ text: String, _ guides: [Guide]) -> Guide? {
        let said = " " + plain(text) + " "
        return guides.first { g in g.matches.contains { m in let f = plain(m); return !f.isEmpty && said.contains(" " + f + " ") } }
    }
    static func plain(_ s: String) -> String { fold(String(s.map { $0.isLetter || $0.isNumber ? $0 : " " })) }
}
