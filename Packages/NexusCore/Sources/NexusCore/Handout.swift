import Foundation

/// A scanned handout (the camera's document scan made into a PDF printout on a board): the page size it is printed at, where each
/// line of read text sits on the page, and the name the PDF is given, from the handout's own title when one can be read.
public enum Handout {
    /// One line of text read from a page; `box` is where it is, as Vision gives it: 0...1 of the page, from the bottom left.
    public struct Line: Equatable {
        public var text: String
        public var x, y, w, h: Double
        public init(_ text: String, x: Double, y: Double, w: Double, h: Double) {
            self.text = text
            self.x = x; self.y = y; self.w = w; self.h = h
        }
    }

    /// A page in PDF points: US Letter's width (612, as the board's printouts expect), the picture's own shape.
    public static func pageSize(width: Double, height: Double) -> (w: Double, h: Double) {
        guard width > 0, height > 0 else { return (612, 792) }
        return (612, (612 * height / width).rounded())
    }

    /// How many pixels wide a scanned page is kept: sharp at the board's 300 % zoom, a few hundred KB a page as a JPEG.
    public static let keepWidth: Double = 1800

    /// Where a read line sits on a page of `w` × `h` points, from the top left (x, y, width, height).
    public static func rect(_ l: Line, pageW w: Double, pageH h: Double) -> (x: Double, y: Double, w: Double, h: Double) {
        (l.x * w, (1 - l.y - l.h) * h, l.w * w, l.h * h)
    }

    /// The handout's title, for the PDF's name: the biggest line in the top part of the first page that reads as words (not a
    /// "Name: ______" line, a page number or a date). Nil when there isn't one, so the caller falls back to a dated name.
    public static func title(_ firstPage: [Line]) -> String? {
        let candidates = firstPage.filter { l in
            guard l.y + l.h >= 0.55 else { return false } // in the top 45 % of the page
            return readsAsTitle(l.text)
        }
        // the tallest line wins; nearly as tall (within 10 %) and higher up wins over it
        let best = candidates.max { a, b in
            if abs(a.h - b.h) <= 0.1 * max(a.h, b.h) { return a.y < b.y }
            return a.h < b.h
        }
        return best.map { clean($0.text) }
    }

    /// The name for a scan's PDF (and its board): its title, else "Handout 2026-11-12 1405".
    public static func name(_ firstPage: [Line], at date: Date, calendar: Calendar = .current) -> String {
        if let t = title(firstPage), !t.isEmpty { return t }
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "Handout %04d-%02d-%02d %02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    static func readsAsTitle(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        let letters = t.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letters >= 4, t.count <= 90 else { return false }
        if t.contains("___") || t.contains("....") { return false } // a line to fill in
        let low = t.lowercased()
        // "Name:", "Date : 12/11", "Teacher" alone (but "Names of the elements" reads fine)
        for field in ["name", "date", "class", "period", "teacher", "student"] where low.hasPrefix(field) {
            let rest = low.dropFirst(field.count).trimmingCharacters(in: .whitespaces)
            if rest.isEmpty || rest.hasPrefix(":") { return false }
        }
        // "Page 2 of 4"
        if low.hasPrefix("page "), low.dropFirst(5).first?.isNumber == true { return false }
        return Double(letters) >= Double(t.count) * 0.45 // mostly words, not numbers and symbols
    }

    /// Spaces tidied and the length kept to a file name's (cut at a word, at most 48 characters).
    static func clean(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: ":;,.-–— "))
        guard t.count > 48 else { return t }
        let cut = String(t.prefix(48))
        if let sp = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: sp) >= 20 { return String(cut[..<sp]) }
        return cut
    }
}
