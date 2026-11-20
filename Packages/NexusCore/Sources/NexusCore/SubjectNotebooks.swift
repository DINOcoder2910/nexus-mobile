import Foundation

/// Which notebooks a subject (a workstream) holds in the new look's sidebar, where each subject keeps its tasks, notebooks, study
/// and files together. Notebooks live apart from workstreams in the data folder (`notebooks/`), so they are matched by name: a
/// notebook belongs to "Chemistry HL" when its name is the subject's ("Chemistry", "Chem HL"), or one of the subject's aliases.
/// Words like HL, SL, AA, ab initio don't count, and a word of four letters or more matches a longer one it begins
/// ("Math" and "Maths", "Chem" and "Chemistry"). Pure.
public enum SubjectNotebooks {
    /// Words that tell a course's level, not its subject.
    static let quiet: Set<String> = ["hl", "sl", "aa", "ai", "ab", "initio", "a", "b", "the", "and", "of", "ib", "dp", "class", "notes", "notebook"]

    /// The words that say what a name is about: lowercased, letters and digits only, the quiet ones dropped.
    public static func words(_ name: String) -> [String] {
        let parts = name.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init)
        let kept = parts.filter { !quiet.contains($0) }
        return kept.isEmpty ? parts : kept
    }

    /// Two words name the same thing: equal, or one begins the other and the shorter has four letters or more.
    static func same(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let (s, l) = a.count <= b.count ? (a, b) : (b, a)
        return s.count >= 4 && l.hasPrefix(s)
    }

    /// A notebook's name belongs to a subject named `name` (with `aliases`): the notebook's first word is the subject's first word
    /// (or an alias's), and every other word of the notebook's is one of the subject's.
    public static func belongs(_ notebook: String, to name: String, aliases: [String] = []) -> Bool {
        let nb = words(notebook)
        guard let first = nb.first else { return false }
        for candidate in [name] + aliases {
            let w = words(candidate)
            guard let head = w.first, same(first, head) else { continue }
            if nb.dropFirst().allSatisfy({ x in w.contains { same(x, $0) } }) { return true }
        }
        return false
    }

    /// The notebooks a subject holds, from `candidates` (notebook paths, "notebooks/Chemistry" or "notebooks/School/Chemistry"),
    /// in their order. A notebook inside one that already belongs is left out (it shows inside it).
    public static func match(name: String, aliases: [String] = [], candidates: [String]) -> [String] {
        var out: [String] = []
        for p in candidates where belongs((p as NSString).lastPathComponent, to: name, aliases: aliases) {
            if out.contains(where: { p.hasPrefix($0 + "/") }) { continue }
            out.append(p)
        }
        return out
    }
}
