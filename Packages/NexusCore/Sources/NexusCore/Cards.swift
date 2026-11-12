import Foundation

/// Study things made from a board's typed words (nexus docs/board-writing.md "Flashcards and Nexus tasks"; ports of the laptop's
/// renderer/src/board/cards.js): the words split into a card's front and back, and a Nexus task chip `[title](nexus-task:<id>)`
/// (made only when asked: a checkbox never becomes a task by itself).
public enum Cards {
    static func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
    static let spaces = re("\\s+")
    static let cardA = re("^(.+?)\\s*(?:—|–|->|→|=|:)\\s+(.+)$")
    static let cardB = re("^(.+?)\\s+(?:—|–|-)\\s+(.+)$")
    static let lead = re("^\\s*(?:[-*+]\\s+(?:\\[[ xX]\\]\\s+)?|\\d+[.)]\\s+|#{1,6}\\s+|>\\s?)")
    static let link = re("\\[([^\\]]*)\\]\\([^)]*\\)")
    static let marks = re("[*_`~]|==")

    static func replace(_ r: NSRegularExpression, _ s: String, _ with: String) -> String {
        r.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: with)
    }

    /// Selected words as a card: "front — back", "front: back", "front = back", "front -> back", else all of it on the front.
    public static func split(_ text: String) -> (front: String, back: String) {
        let s = replace(spaces, text, " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let ns = s as NSString
        for r in [cardA, cardB] {
            if let m = r.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
                return (ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines),
                        ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return (s, "")
    }

    /// A line's words as a task title: no list mark, no checkbox, no heading or quote mark, no markdown.
    public static func taskTitle(_ line: String) -> String {
        var s = replace(lead, line, "")
        s = replace(link, s, "$1")
        s = replace(marks, s, "")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The chip written into a block for a task.
    public static func taskChip(_ title: String, id: String) -> String {
        "[" + title.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "") + "](nexus-task:\(id))"
    }
}
