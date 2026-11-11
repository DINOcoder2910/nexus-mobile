import Foundation

/// A typed block's look, the same as the laptop's `renderer/src/board/text.js` (its tests are dev/unit-board.mjs): its size, colour
/// and background as the item stores them (`size` px, `color` and `fill` "#RRGGBB"), and ticking a checkbox in its markdown. The words
/// are markdown in text/<id>.md; the look is the item's own, so the file stays a plain note.
public enum TextLook {
    public static let sizes: [(px: Double, label: String)] = [(13, "Small"), (16, "Normal"), (22, "Large"), (32, "Huge")]
    public static let colors: [(hex: String, label: String)] = [
        ("#1B1B1B", "Black"), ("#6B6B6B", "Grey"), ("#1F5FD1", "Blue"), ("#D93025", "Red"), ("#188038", "Green"),
        ("#8E44AD", "Purple"), ("#C26A00", "Orange"),
    ]
    public static let fills: [(hex: String, label: String)] = [
        ("", "None"), ("#FFF4B8", "Yellow"), ("#D9F5DD", "Green"), ("#DCEBFF", "Blue"), ("#FFE0EC", "Pink"), ("#EFEFEF", "Grey"),
    ]
    public static let defaultSize: Double = 16

    /// "#" and six hex digits, either case (the laptop's /^#[0-9a-f]{6}$/i).
    public static func isHex(_ s: String) -> Bool {
        let u = Array(s.unicodeScalars)
        guard u.count == 7, u[0] == "#" else { return false }
        for c in u.dropFirst() {
            let ok = (c >= "0" && c <= "9") || (c >= "a" && c <= "f") || (c >= "A" && c <= "F")
            if !ok { return false }
        }
        return true
    }

    /// The look an item asks for, checked (nil for the default), like textLook: a size from 8 to 200 (a number, or a string of one),
    /// colours that are "#RRGGBB".
    public static func look(_ item: BoardItem) -> (size: Double?, color: String?, fill: String?) {
        var n: Double? = nil
        switch item.json["size"] {
        case .number(let v)?: n = v
        case .string(let s)?: n = Double(s.trimmingCharacters(in: .whitespacesAndNewlines))
        default: n = nil
        }
        var size: Double? = nil
        if let v = n, v.isFinite, v >= 8, v <= 200 { size = v }
        let color: String? = item.string("color").flatMap { isHex($0) ? $0 : nil }
        let fill: String? = item.string("fill").flatMap { isHex($0) ? $0 : nil }
        return (size, color, fill)
    }

    /// The item with one look changed, like withLook: nil, "" or the default size takes the key off (so a plain block stays plain);
    /// a size is written as a number, colours in upper case.
    public static func with(_ item: BoardItem, _ key: String, _ value: String?) -> BoardItem {
        guard let value, !value.isEmpty else { return item.with(key, nil) }
        if key == "size" {
            guard let n = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)), n.isFinite, n != defaultSize else {
                return item.with(key, nil)
            }
            return item.with(key, .number(n))
        }
        return item.with(key, .string(value.uppercased()))
    }

    private static let taskPattern: NSRegularExpression? = try? NSRegularExpression(
        pattern: "^((?:\\s*>\\s*)*\\s*(?:[-*+]|\\d+[.)])\\s+\\[)([ xX])(\\]\\s)", options: [])

    /// The markdown with the task on line `line` (0-based) ticked or unticked; nil when that line is not a task.
    public static func toggleTask(_ md: String, line: Int) -> String? {
        var lines: [String] = md.components(separatedBy: "\n")
        guard line >= 0, line < lines.count, let re = taskPattern else { return nil }
        let l = lines[line]
        let ns = l as NSString
        guard let m = re.firstMatch(in: l, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        let head = ns.substring(with: m.range(at: 1))
        let mark = ns.substring(with: m.range(at: 2))
        let tail = ns.substring(with: m.range(at: 3))
        let rest = ns.substring(from: m.range.location + m.range.length)
        lines[line] = head + (mark == " " ? "x" : " ") + tail + rest
        return lines.joined(separator: "\n")
    }
}
