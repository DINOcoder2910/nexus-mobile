import Foundation

/// What a block's words come to, as the laptop counts them (a port of `plainText`, `wordCount`, `charCount`, `langOf` and
/// `chipFacts` in nexus renderer/src/board/blocks.js), so the two devices show the same counts and the same folded chip.
public enum BlockFacts {
    static func replace(_ s: String, _ pattern: String, _ with: String, options: NSRegularExpression.Options = []) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: with)
    }

    static func matches(_ s: String, _ pattern: String, options: NSRegularExpression.Options = []) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    /// The words a reader sees: markdown marks, links' targets, CriticMarkup's deleted words and code fences left out.
    public static func plainText(_ md: String) -> String {
        var t = md
        t = replace(t, #"^\s*(```|~~~)[^\n]*$"#, "", options: .anchorsMatchLines)
        t = replace(t, #"\{--[\s\S]*?--\}"#, "")
        t = replace(t, #"\{~~([\s\S]*?)~>([\s\S]*?)~~\}"#, "$2")
        t = replace(t, #"\{\+\+([\s\S]*?)\+\+\}"#, "$1")
        t = replace(t, #"!\[[^\]]*\]\([^)]*\)"#, "")
        t = replace(t, #"\[([^\]]*)\]\([^)]*\)"#, "$1")
        t = replace(t, #"<[^>]+>"#, "")
        t = replace(t, #"^\s{0,3}(#{1,6}\s+|>\s?|[-*+]\s+\[[ xX]\]\s+|[-*+]\s+|\d+[.)]\s+)"#, "", options: .anchorsMatchLines)
        t = replace(t, #"[*_~=`]"#, "")
        return t
    }

    public static func wordCount(_ md: String) -> Int { matches(plainText(md), #"[\p{L}\p{N}][\p{L}\p{N}'’-]*"#).count }
    public static func charCount(_ md: String) -> Int { plainText(md).filter { !$0.isWhitespace }.utf16.count }

    static let esWords: Set<String> = Set("el la los las un una unos unas y o pero que de del en con por para es son está están estoy soy eres fue era muy también porque cuando donde como más mi mis tu tus su sus yo nosotros ellos ella hay me te se le lo nos al este esta estos estas ese esa hola gracias bueno buena".split(separator: " ").map(String.init))
    static let enWords: Set<String> = Set("the a an and or but that of in on with for is are was were be been to it this these those i you he she we they my your his her our their there have has had not do does did at by from as if so what when where which who".split(separator: " ").map(String.init))

    /// "es", "en" or nil: the block's own `lang`, else what its words look like.
    public static func lang(_ item: BoardItem?, _ md: String) -> String? {
        if let l = item?.string("lang"), l == "es" || l == "en" { return l }
        let words = matches(plainText(md).lowercased(), #"\p{L}+"#).prefix(400)
        if words.count < 3 { return nil }
        var es = 0, en = 0
        for w in words {
            if esWords.contains(w) { es += 1 }
            if enWords.contains(w) { en += 1 }
            if w.contains(where: { "áéíóúñ¿¡".contains($0) }) { es += 2 }
        }
        if md.contains(where: { "¿¡".contains($0) }) { es += 3 }
        return Double(es) > Double(en) * 1.2 && es >= 2 ? "es" : en >= 1 ? "en" : nil
    }

    public struct Chip: Equatable, Sendable {
        public var title: String
        public var line: String
        /// "checklist", "spanish", "heading" or "text" (the chip's icon).
        public var kind: String
    }

    /// A folded block's chip: its title (first heading, else first words, 60 at most) and a line about it.
    public static func chip(_ item: BoardItem?, _ md: String) -> Chip {
        let lines = md.components(separatedBy: "\n")
        let head = lines.first { !matches($0, #"^#{1,6}\s+\S"#).isEmpty }
        let first = plainText(head ?? lines.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var title = first
        if first.count > 60 { title = replace(String(first.prefix(57)), #"\s+\S*$"#, "") + "…" }
        if title.isEmpty { title = "Empty block" }
        let tasks = matches(md, #"^\s*[-*+]\s+\[[ xX]\]"#, options: .anchorsMatchLines)
        let done = tasks.filter { $0.contains("[x]") || $0.contains("[X]") }.count
        var facts: [String] = []
        let n = wordCount(md)
        facts.append(n == 1 ? "1 word" : "\(n) words")
        if !tasks.isEmpty { facts.append("\(done) of \(tasks.count) done") }
        let l = lang(item, md)
        if l == "es" { facts.append("Spanish") }
        let ds = item?.json["drafts"]?.array ?? []
        if ds.count > 1 {
            let k = ds.firstIndex { $0["id"]?.string == item?.string("draft") }
            facts.append("Draft \((k ?? ds.count - 1) + 1) of \(ds.count)")
        }
        return Chip(title: title, line: facts.joined(separator: " · "), kind: !tasks.isEmpty ? "checklist" : l == "es" ? "spanish" : head != nil ? "heading" : "text")
    }
}
