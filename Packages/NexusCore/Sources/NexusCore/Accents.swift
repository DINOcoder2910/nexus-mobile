import Foundation

/// Word's accent keys, as the laptop has them (nexus docs/board-writing.md "Accents"): a dead key, then a letter.
/// On the iPad: ⌘' then a vowel (á), ⌘⇧~ then n (ñ), ⌘⇧: then u (ü), ⌘⌥⇧? (¿) and ⌘⌥⇧! (¡).
public enum Accents {
    public static let keys: [String: [String: String]] = [
        "acute": ["a": "á", "e": "é", "i": "í", "o": "ó", "u": "ú", "A": "Á", "E": "É", "I": "Í", "O": "Ó", "U": "Ú"],
        "tilde": ["n": "ñ", "N": "Ñ", "a": "ã", "o": "õ"],
        "umlaut": ["u": "ü", "U": "Ü", "a": "ä", "o": "ö", "e": "ë", "i": "ï"],
    ]

    /// What typing `typed` after the dead key `dead` gives: the accented letter, or the letter as typed.
    public static func apply(_ dead: String, _ typed: String) -> String { keys[dead]?[typed] ?? typed }

    /// The letters a Spanish block's row offers.
    public static let spanishRow = ["á", "é", "í", "ó", "ú", "ñ", "ü", "¿", "¡"]
}

/// Practice mode (a text item's `practice`: `{"min": 30, "started": "ISO time"}`): checks, spelling, autocorrect and Writing Tools
/// off, with a timer.
public enum Practice {
    public static func minutes(_ item: BoardItem) -> Double? {
        guard let p = item.json["practice"], let m = p["min"]?.number, m > 0 else { return nil }
        return m
    }

    public static func started(_ item: BoardItem) -> Date? {
        guard let s = item.json["practice"]?["started"]?.string else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    public static func isOn(_ item: BoardItem) -> Bool { minutes(item) != nil }

    /// Seconds left (never below 0), or nil when practice is off.
    public static func left(_ item: BoardItem, now: Date = Date()) -> Double? {
        guard let m = minutes(item) else { return nil }
        let start = started(item) ?? now
        return max(0, m * 60 - now.timeIntervalSince(start))
    }

    public static func field(minutes: Double, now: Date = Date()) -> JSONValue {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
        return .object([("min", .number(minutes)), ("started", .string(f.string(from: now)))])
    }

    /// "12:05" for a number of seconds.
    public static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
