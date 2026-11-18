import Foundation

/// Adding a card to a Spanish deck (Add to vocab on a word, the tutor's card offers, Add a card): Claude's draft, the card rules checked
/// (shown, never enforced), and the deck file with one more card at the end of `cards:`, its comments and other cards left as they were.
/// A port of the laptop's spanishcore.js draftCard, cardWarnings, cardId and addCardText.
public enum SpanishCards {
    public struct Draft: Equatable, Sendable {
        public var front: String
        public var back: String
        public var deck: String
        public var tags: [String]
        public var example: String
        public init(front: String = "", back: String = "", deck: String = "es-nucleo", tags: [String] = [], example: String = "") {
            self.front = front; self.back = back; self.deck = deck; self.tags = tags; self.example = example
        }
    }

    static let article = #"^(el|la|los|las|un|una|unos|unas)\s"#

    /// A draft from a checked word ({ word, lemma, form, meaning }): a noun gets its article from the form Claude gave
    /// ("feminine singular noun"); the base form is singular (la maleta for "maletas"), only a word with no base form keeps its number.
    public static func draft(word: String, lemma: String = "", form: String = "", meaning: String = "", example: String = "", deck: String = "es-nucleo") -> Draft {
        let f = form.lowercased()
        var front = (lemma.isEmpty ? word : lemma).trimmed
        var tags: [String] = []
        if JS.test(#"\bnoun|sustantivo"#, f) {
            tags.append("pos::sustantivo")
            if !JS.test(article, front, ci: true) {
                let fem = JS.test("feminine|femenin", f), pl = lemma.isEmpty && JS.test("plural", f)
                if fem || JS.test("masculine|masculin", f) { front = (fem ? (pl ? "las " : "la ") : (pl ? "los " : "el ")) + front }
            }
        } else if JS.test(#"\bverb|verbo|infinitive"#, f) { tags.append("pos::verbo") }
        else if JS.test("adjective|adjetivo", f) { tags.append("pos::adjetivo") }
        else if JS.test("adverb", f) { tags.append("pos::adverbio") }
        else if JS.test("connector|conjunction", f) { tags.append("pos::conector") }
        return Draft(front: front, back: meaning.trimmed, deck: deck, tags: tags, example: example.trimmed)
    }

    /// A card already in a deck, for the "already a card" rule.
    public struct Existing: Equatable, Sendable {
        public var front, back, deck: String
        public init(front: String, back: String, deck: String) { self.front = front; self.back = back; self.deck = deck }
    }

    /// What breaks the card rules (shown, never enforced: the user decides).
    public static func warnings(front: String, back: String, tags: [String], existing: [Existing] = []) -> [String] {
        var out: [String] = []
        let f = front.trimmed, b = back.trimmed
        if f.isEmpty || b.isEmpty { out.append("A card needs both sides.") }
        if tags.contains("pos::sustantivo") && !f.isEmpty && !JS.test(article, f, ci: true) { out.append("Nouns carry their article (el, la, los, las).") }
        if JS.test("[,;/]", f) && JS.split("[,;/]", f).count > 2 { out.append("One thing per card: this looks like a list.") }
        func bare(_ s: String) -> String { JS.replace(article, JS.strip(s).lowercased(), "", ci: true).trimmed }
        let key = bare(f)
        if !f.isEmpty, let dup = existing.first(where: { bare($0.front) == key }) {
            out.append("Already a card\(dup.deck.isEmpty ? "" : " in " + dup.deck): \(dup.front) = \(dup.back).")
        }
        return out
    }

    public static func cardId(_ front: String, taken: [String] = []) -> String {
        var base = JS.replace(article, JS.strip(front).lowercased(), "", ci: true)
        base = JS.replace("[^a-z0-9]+", base, "-")
        base = JS.replace("^-+|-+$", base, "")
        base = String(base.prefix(40))
        if base.isEmpty { base = "card" }
        let set = Set(taken)
        var id = base, n = 2
        while set.contains(id) { id = "\(base)-\(n)"; n += 1 }
        return id
    }

    /// The deck file with one more card at the end of `cards:`; the file's comments, settings and other cards stay as they were.
    /// Throws when the deck does not parse (nothing is written then).
    public static func addCardText(_ text: String, front: String, back: String, tags: [String] = [], example: String = "", day: String? = nil) throws -> (text: String, id: String) {
        let src = text.isEmpty ? "cards: []\n" : text
        let parsed = try YValue.parse(src)
        let taken = (parsed["cards"]?.list ?? []).map { $0["id"]?.str ?? "" }
        let id = cardId(front, taken: taken)
        var seen = Set<String>()
        let clean = tags.map(Spanish.cleanTag).filter { !$0.isEmpty && seen.insert($0).inserted }
        var fields: [String] = ["id: \(SpanishYAML.scalar(id))", "front: \(SpanishYAML.scalar(front.trimmed))", "back: \(SpanishYAML.scalar(back.trimmed))"]
        if !clean.isEmpty { fields.append("tags: [ \(clean.map(SpanishYAML.scalar).joined(separator: ", ")) ]") }
        if !example.trimmed.isEmpty { fields.append("example: \(SpanishYAML.scalar(example.trimmed))") }
        if let day, !day.isEmpty { fields.append("added: \(SpanishYAML.scalar(day))") }

        var lines = src.components(separatedBy: "\n")
        let endsWithNewline = lines.last == ""
        if endsWithNewline { lines.removeLast() }
        func card(_ indent: String) -> [String] {
            [indent + "- " + fields[0]] + fields.dropFirst().map { indent + "  " + $0 }
        }
        if let k = lines.firstIndex(where: { JS.test(#"^cards:\s*(\[\s*\])?\s*(#.*)?$"#, $0) }) {
            let flowEmpty = JS.test(#"^cards:\s*\[\s*\]"#, lines[k])
            if flowEmpty {
                lines[k] = "cards:"
                lines.insert(contentsOf: card("  "), at: k + 1)
            } else {
                // the block under cards: runs while lines are indented, list items, comments or blank
                var end = k + 1, indent: String?
                while end < lines.count {
                    let l = lines[end]
                    if l.trimmed.isEmpty || l.hasPrefix(" ") || l.hasPrefix("-") || l.hasPrefix("#") || l.hasPrefix("\t") {
                        if indent == nil, let m = JS.match(#"^(\s*)- "#, l) { indent = m[1] }
                        end += 1
                    } else { break }
                }
                // after the last card, before any blank lines or comments that close the block
                var at = end
                while at > k + 1, lines[at - 1].trimmed.isEmpty || lines[at - 1].hasPrefix("#") { at -= 1 }
                lines.insert(contentsOf: card(indent ?? "  "), at: at)
            }
        } else if JS.test(#"^cards:"#, src) || lines.contains(where: { $0.hasPrefix("cards:") }) {
            // cards written as a flow list with cards in it: not changed by hand here
            throw SpanishYAML.Failure(message: "its cards are written on one line ([ … ]); add this card on the laptop")
        } else {
            lines.append("cards:")
            lines += card("  ")
        }
        let out = lines.joined(separator: "\n") + "\n"
        // the result must read back with the new card in it
        guard StudyDeck.parse(out).deck?.cards.contains(where: { $0.id == id }) == true else {
            throw SpanishYAML.Failure(message: "the card could not be put in its cards: list")
        }
        return (out, id)
    }
}
