import Foundation

/// Chemistry typed in a block: `H2O` becomes `H₂O` and `SO4^2-` becomes `SO₄²⁻` when the word ends, only in a word that reads as a
/// formula (every letter part is an element symbol). The file stores the Unicode, so it reads the same anywhere; undo straight after
/// takes it back. Off per block with `"chem": false`. The laptop's board writing has the same rule and the same test table.
public enum Chem {
    public static let elements: Set<String> = [
        "H", "He", "Li", "Be", "B", "C", "N", "O", "F", "Ne", "Na", "Mg", "Al", "Si", "P", "S", "Cl", "Ar", "K", "Ca",
        "Sc", "Ti", "V", "Cr", "Mn", "Fe", "Co", "Ni", "Cu", "Zn", "Ga", "Ge", "As", "Se", "Br", "Kr", "Rb", "Sr", "Y", "Zr",
        "Nb", "Mo", "Tc", "Ru", "Rh", "Pd", "Ag", "Cd", "In", "Sn", "Sb", "Te", "I", "Xe", "Cs", "Ba", "La", "Ce", "Pr", "Nd",
        "Pm", "Sm", "Eu", "Gd", "Tb", "Dy", "Ho", "Er", "Tm", "Yb", "Lu", "Hf", "Ta", "W", "Re", "Os", "Ir", "Pt", "Au", "Hg",
        "Tl", "Pb", "Bi", "Po", "At", "Rn", "Fr", "Ra", "Ac", "Th", "Pa", "U", "Np", "Pu", "Am", "Cm", "Bk", "Cf", "Es", "Fm",
        "Md", "No", "Lr", "Rf", "Db", "Sg", "Bh", "Hs", "Mt", "Ds", "Rg", "Cn", "Nh", "Fl", "Mc", "Lv", "Ts", "Og",
    ]

    static let sub: [Character: Character] = ["0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉"]
    static let sup: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
                                              "+": "⁺", "-": "⁻", "−": "⁻"]

    /// The formula written with sub- and superscripts, or nil when the word isn't a formula or has nothing to change.
    public static func formula(_ word: String) -> String? {
        let c = Array(word)
        var i = 0
        var out = ""
        // a coefficient stays as it is: 2H2O
        while i < c.count, c[i].isASCII, c[i].isNumber { out.append(c[i]); i += 1 }
        var symbols = 0
        var changed = false
        var depth = 0
        var lastWasPart = false
        while i < c.count {
            let ch = c[i]
            if ch.isUppercase, ch.isASCII {
                var sym = String(ch)
                if i + 1 < c.count, c[i + 1].isLowercase, c[i + 1].isASCII, elements.contains(sym + String(c[i + 1])) {
                    sym += String(c[i + 1])
                    i += 1
                } else if i + 1 < c.count, c[i + 1].isLowercase {
                    return nil
                }
                guard elements.contains(sym) else { return nil }
                out += sym
                symbols += 1
                i += 1
                lastWasPart = true
            } else if ch == "(" || ch == "[" {
                depth += 1
                out.append(ch)
                i += 1
                lastWasPart = false
            } else if ch == ")" || ch == "]" {
                guard depth > 0, lastWasPart else { return nil }
                depth -= 1
                out.append(ch)
                i += 1
                lastWasPart = true
            } else if ch.isASCII, ch.isNumber {
                guard lastWasPart else { return nil }
                while i < c.count, c[i].isASCII, c[i].isNumber {
                    out.append(sub[c[i]] ?? c[i])
                    i += 1
                }
                changed = true
                lastWasPart = false
            } else if ch == "^" {
                // a charge: ^2-, ^+, ^3+ (the rest of the word)
                guard symbols > 0, i + 1 < c.count else { return nil }
                var j = i + 1
                var charge = ""
                while j < c.count, c[j].isASCII, c[j].isNumber { charge.append(sup[c[j]] ?? c[j]); j += 1 }
                guard j < c.count, c[j] == "+" || c[j] == "-" || c[j] == "−", j + 1 == c.count else { return nil }
                charge.append(sup[c[j]] ?? c[j])
                out += charge
                i = j + 1
                changed = true
            } else if ch == "·" || ch == ".", i + 1 < c.count, c[i + 1].isNumber || c[i + 1].isUppercase {
                // a hydrate: CuSO4·5H2O
                out.append("·")
                i += 1
                while i < c.count, c[i].isASCII, c[i].isNumber { out.append(c[i]); i += 1 }
                lastWasPart = false
            } else {
                return nil
            }
        }
        guard depth == 0, symbols > 0, changed else { return nil }
        return out
    }

    /// The characters that end a word, after which a formula is written out.
    public static func endsWord(_ c: Character) -> Bool {
        c.isWhitespace || c == "," || c == "." || c == ";" || c == ":" || c == "!" || c == "?"
    }

    /// Typing just put `typed` in at `caret - 1`: if it ends a word and the word before it is a formula, the change to make (the
    /// word's range in UTF-16 and what it becomes). Nil otherwise.
    public static func convert(_ text: String, caret: Int) -> (range: NSRange, with: String)? {
        let t = text as NSString
        guard caret >= 2, caret <= t.length else { return nil }
        let typed = t.substring(with: NSRange(location: caret - 1, length: 1))
        guard let ch = typed.first, endsWord(ch) else { return nil }
        var start = caret - 1
        // a sentence's full stop after a formula: "H2O." — the word stops before it
        while start > 0 {
            let c = t.character(at: start - 1)
            if c == 32 || c == 10 || c == 9 || c == 44 || c == 59 || c == 58 || c == 33 || c == 63 || c == 0xA0 { break }
            start -= 1
        }
        var end = caret - 1
        // a full stop typed after "H2O" is the word's end; a trailing "." inside is not part of the formula
        while end > start, t.character(at: end - 1) == 46 { end -= 1 }
        guard end > start else { return nil }
        let word = t.substring(with: NSRange(location: start, length: end - start))
        // don't touch a word in code, a link or maths
        if word.contains("`") || word.contains("$") || word.contains("](") { return nil }
        guard let f = formula(word), f != word else { return nil }
        return (NSRange(location: start, length: end - start), f)
    }
}
