import Foundation

/// Chemistry as you type (nexus docs/board-writing.md "Chemistry as you type"; a line-for-line port of `chemWord` and `chemBefore` in
/// the laptop's renderer/src/board/blocks.js, checked against the same table). When a word ends, a formula in it is written with
/// Unicode subscripts and superscripts, and those are what the file keeps.
public enum Chem {
    static let elements: Set<String> = Set(("H He Li Be B C N O F Ne Na Mg Al Si P S Cl Ar K Ca Sc Ti V Cr Mn Fe Co Ni Cu Zn Ga Ge As Se Br Kr Rb Sr Y Zr Nb Mo Tc Ru Rh Pd Ag Cd In Sn Sb Te I Xe Cs Ba La Ce Pr Nd Pm Sm Eu Gd Tb Dy Ho Er Tm Yb Lu Hf Ta W Re Os Ir Pt Au Hg Tl Pb Bi Po At Rn Fr Ra Ac Th Pa U Np Pu Am Cm Bk Cf Es Fm Md No Lr").split(separator: " ").map(String.init))
    /// One element alone with a number is converted only for the molecules people write that way (P2, B2, S1 stay).
    static let lone: Set<String> = ["H2", "N2", "O2", "O3", "F2", "Cl2", "Br2", "I2", "P4", "S8", "C60"]
    static let subs: [Character: Character] = ["0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉"]
    static let sups: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "+": "⁺", "-": "⁻"]
    static func sub(_ d: String) -> String { String(d.map { subs[$0] ?? $0 }) }
    static func sup(_ d: String) -> String { String(d.map { sups[$0] ?? $0 }) }

    static func match(_ pattern: String, _ s: String) -> [String?]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
    }

    private struct Part { var t: String; var s: String }

    /// A typed word with its formula written (H2O → H₂O, SO4^2- → SO₄²⁻, Fe3+ → Fe³⁺, 2e- → 2e⁻), or nil when it is not a formula.
    public static func formula(_ word: String) -> String? {
        if let m = match(#"^(\d*)e-$"#, word) { return (m[1] ?? "") + "e⁻" }
        guard let m = match(#"^(\d*)([A-Za-z0-9()\[\]]+?)(?:\^(\d*[+-])|(\d*[+-]))?(\((?:aq|s|l|g)\))?$"#, word) else { return nil }
        let coef = m[1] ?? "", body = Array(m[2] ?? ""), hatCharge = m[3], bareCharge = m[4], state = m[5] ?? ""
        var parts: [Part] = []
        var i = 0, elementCount = 0, depth = 0
        while i < body.count {
            let c = body[i]
            if c == "(" || c == "[" { depth += 1; parts.append(Part(t: "open", s: String(c))); i += 1; continue }
            if c == ")" || c == "]" {
                if depth == 0 { return nil }
                depth -= 1
                parts.append(Part(t: "close", s: String(c))); i += 1; continue
            }
            if c.isASCII, c.isNumber {
                var d = ""
                while i < body.count, body[i].isASCII, body[i].isNumber { d.append(body[i]); i += 1 }
                guard let prev = parts.last, prev.t != "open", prev.t != "n" else { return nil }
                parts.append(Part(t: "n", s: d)); continue
            }
            guard c.isASCII, c.isUppercase else { return nil }
            var s = String(c)
            if i + 1 < body.count, body[i + 1].isASCII, body[i + 1].isLowercase { s.append(body[i + 1]) }
            if !elements.contains(s) {
                if s.count == 2, elements.contains(String(s.first!)) { s = String(s.first!) } else { return nil }
            }
            parts.append(Part(t: "el", s: s)); elementCount += 1; i += s.count
        }
        if depth != 0 || elementCount == 0 { return nil }
        var charge: String? = hatCharge
        if let bare = bareCharge {
            let digits = String(bare.dropLast()), sign = String(bare.suffix(1))
            let isLone = elementCount == 1 && !parts.contains { $0.t == "n" } && !parts.contains { $0.t == "open" }
            let complex = parts.last?.s == "]"
            if isLone || complex || digits.isEmpty { charge = digits + sign }
            else if digits.count == 1 { parts.append(Part(t: "n", s: digits)); charge = sign }
            else { parts.append(Part(t: "n", s: String(digits.dropLast()))); charge = String(digits.suffix(1)) + sign }
            if !isLone, !complex, !digits.isEmpty, parts.count >= 2, parts[parts.count - 2].t == "n" { return nil }
        }
        let hasCount = parts.contains { $0.t == "n" }
        if !hasCount && charge == nil { return nil }
        if parts.contains(where: { $0.t == "n" && ($0.s.hasPrefix("0") || $0.s == "1") }) { return nil }
        if elementCount == 1, charge == nil, !lone.contains(parts.map(\.s).joined()) { return nil }
        if let c = charge, c.count == 2, c.hasPrefix("1"), c.last == "+" || c.last == "-" { charge = String(c.dropFirst()) }
        return coef + parts.map { $0.t == "n" ? sub($0.s) : $0.s }.joined() + (charge.map(sup) ?? "") + state
    }

    /// A typed character that ends a word (the conversion happens then).
    public static func endsWord(_ c: Character) -> Bool { c.isWhitespace || ".,;:!?)]}".contains(c) }

    static func count(_ s: String, _ c: Character) -> Int { s.reduce(0) { $0 + ($1 == c ? 1 : 0) } }

    /// The word that ends at `to` in a line (UTF-16), and its conversion; nil inside `code`, $maths$ or a link, or mid-word.
    public static func before(_ text: String, to: Int) -> (from: Int, to: Int, word: String, out: String)? {
        let ns = text as NSString
        let before = ns.substring(to: min(to, ns.length))
        guard let m = match(#"([0-9A-Za-z()\[\]^+-]+)$"#, before), var word = m[1] else { return nil }
        var from = (before as NSString).length - (word as NSString).length
        // a closing bracket of the sentence is not the formula's: "(see H2O)" -> H2O
        if word.hasSuffix(")"), count(word, "(") < count(word, ")"), match(#"\((aq|s|l|g)\)$"#, word) == nil { word.removeLast() }
        while word.hasPrefix("("), count(word, "(") > count(word, ")") { word.removeFirst(); from += 1 }
        if from > 0 {
            let prev = ns.substring(with: NSRange(location: from - 1, length: 1))
            if match(#"[\w₀-₉⁰-⁹⁺⁻]"#, prev) != nil { return nil }
        }
        let head = ns.substring(to: from)
        let ticks = count(head, "`"), dollars = count(head.replacingOccurrences(of: "\\$", with: ""), "$")
        if ticks % 2 == 1 || dollars % 2 == 1 { return nil }
        if match(#"\]\([^)]*$|https?://\S*$|\[\[[^\]]*$"#, head) != nil { return nil }
        guard let out = formula(word), out != word else { return nil }
        return (from, from + (word as NSString).length, word, out)
    }

    /// After typing a character that ends a word at `caret` (the offset just after it): the formula before it to rewrite.
    public static func convert(_ text: String, caret: Int) -> (range: NSRange, with: String)? {
        let t = text as NSString
        guard caret >= 2, caret <= t.length else { return nil }
        guard let ch = t.substring(with: NSRange(location: caret - 1, length: 1)).first, endsWord(ch) else { return nil }
        // the line up to the word's end
        let line = t.lineRange(for: NSRange(location: caret - 1, length: 0))
        let upto = t.substring(with: NSRange(location: line.location, length: caret - 1 - line.location))
        guard let f = before(upto, to: (upto as NSString).length) else { return nil }
        return (NSRange(location: line.location + f.from, length: f.to - f.from), f.out)
    }
}
