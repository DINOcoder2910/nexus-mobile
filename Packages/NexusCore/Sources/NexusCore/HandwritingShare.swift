import Foundation

/// The words the iPad read in a board's handwriting, shared with the laptop in the board's own folder (`handwriting.json`, nexus
/// docs/data-format.md "Boards"), so the laptop's search finds what was written by hand. Only the iPad writes it (the iPhone and the
/// laptop read no ink); sync carries it like any file. Typed blocks are not in it: every app reads those from `text/` itself.
///
/// `{"format": "nexus-handwriting/1", "device": "iPad", "read": "<ISO time>", "lines": [{"text", "x", "y", "w", "h"}]}`, a line's
/// place in board units (y down), to a tenth.
public enum HandwritingShare {
    public static let file = "handwriting.json"
    public static let format = "nexus-handwriting/1"

    public struct Line: Equatable {
        public var text: String
        public var x: Double
        public var y: Double
        public var w: Double
        public var h: Double
        public init(text: String, x: Double, y: Double, w: Double, h: Double) {
            let r = { (v: Double) in v.isFinite ? (v * 10).rounded() / 10 : 0 }
            self.text = text; self.x = r(x); self.y = r(y); self.w = r(w); self.h = r(h)
        }
    }

    /// The file's text for these lines.
    public static func encode(_ lines: [Line], device: String, read: Date) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let ls = lines.map { l in
            JSONValue.object([("text", .string(l.text)), ("x", .number(l.x)), ("y", .number(l.y)), ("w", .number(l.w)), ("h", .number(l.h))]).text
        }
        return "{\"format\":\(JSONValue.string(format).text),\"device\":\(JSONValue.string(device).text),\"read\":\(JSONValue.string(iso.string(from: read)).text),\n\"lines\":["
            + (ls.isEmpty ? "" : "\n" + ls.joined(separator: ",\n") + "\n") + "]}\n"
    }

    /// The lines a file holds (nil when it isn't one).
    public static func lines(in text: String) -> [Line]? {
        guard let v = try? JSONValue.parse(text), v["format"]?.string == format, let a = v["lines"]?.array else { return nil }
        return a.compactMap { l in
            guard let t = l["text"]?.string else { return nil }
            return Line(text: t, x: l["x"]?.number ?? 0, y: l["y"]?.number ?? 0, w: l["w"]?.number ?? 0, h: l["h"]?.number ?? 0)
        }
    }

    /// Keeps the board's file in step with these lines: written when they differ from what it holds, removed when there are none.
    /// True when the folder changed (an unchanged board is never written again, so sync has nothing to carry).
    @discardableResult
    public static func write(_ lines: [Line], board: URL, device: String, now: Date = Date()) throws -> Bool {
        let url = board.appendingPathComponent(file)
        let old = try? String(contentsOf: url, encoding: .utf8)
        if lines.isEmpty {
            guard old != nil else { return false }
            try FileManager.default.removeItem(at: url)
            return true
        }
        if let o = old, let had = HandwritingShare.lines(in: o), had == lines { return false }
        try encode(lines, device: device, read: now).write(to: url, atomically: true, encoding: .utf8)
        return true
    }
}
