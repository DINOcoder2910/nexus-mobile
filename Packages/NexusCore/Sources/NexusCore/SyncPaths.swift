import Foundation

/// Which files sync, and which paths every device can use (the Nexus repo's docs/sync.md, "What is synced" and "Paths").
/// The laptop's renderer/src/sync/paths.js keeps the same lists, and matches names the same way (ignoring letter case),
/// so a path one side ignores is never sent or written by the other.
public enum SyncPaths {
    /// Folders skipped anywhere in the tree (compared in lower case).
    public static let ignoredFolders: Set<String> = [
        ".git", ".nexus", ".import", "node_modules", ".sync", ".stfolder", ".stversions",
        ".trash", ".trashes", ".fseventsd", ".spotlight-v100",
    ]
    static let ignoredNames: Set<String> = [".ds_store", "thumbs.db", "desktop.ini"]
    static let ignoredSuffixes = [".tmp", ".renaming", ".partial"]
    static let ignoredPrefixes = ["~$", ".~lock.", ".syncthing."]
    static let forbidden = Set("\\<>:\"|?*".unicodeScalars)
    /// Counted in UTF-16 units, as JavaScript's `length` counts them.
    public static let maxLength = 400

    /// A folder the scan never enters.
    public static func isIgnoredFolder(_ name: String) -> Bool { ignoredFolders.contains(name.lowercased()) }

    /// A file name that never syncs (lock files, temp files, Finder and Explorer litter).
    public static func isIgnoredName(_ name: String) -> Bool {
        let n = name.lowercased()
        if ignoredNames.contains(n) || ignoredFolders.contains(n) { return true }
        if ignoredSuffixes.contains(where: { n.hasSuffix($0) }) { return true }
        return ignoredPrefixes.contains(where: { n.hasPrefix($0) })
    }

    /// True when a relative path is skipped: inside an ignored folder, or an ignored file name.
    public static func isIgnored(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if parts.dropLast().contains(where: isIgnoredFolder) { return true }
        guard let name = parts.last else { return true }
        return isIgnoredName(name)
    }

    /// A safe protocol path: relative, `/`-separated, NFC, no empty, `.` or `..` segment, no backslash, control character or
    /// any of `< > : " | ? *`, no segment ending in a space or a dot, at most 400 characters.
    public static func isSafe(_ path: String) -> Bool {
        if path.isEmpty || path.utf16.count > maxLength { return false }
        if !path.unicodeScalars.elementsEqual(nfc(path).unicodeScalars) { return false }
        for s in path.unicodeScalars where s.value < 0x20 || s.value == 0x7F || forbidden.contains(s) { return false }
        for seg in path.split(separator: "/", omittingEmptySubsequences: false) {
            if seg.isEmpty || seg == "." || seg == ".." || seg.hasSuffix(" ") || seg.hasSuffix(".") { return false }
        }
        return true
    }

    /// The NFC form of a name (a file made on a Mac or by some apps can be NFD on disk).
    public static func nfc(_ s: String) -> String { s.precomposedStringWithCanonicalMapping }

    private static let conflictPattern = try! NSRegularExpression(pattern: " \\(conflict [^)]*\\)(\\.[^./]*)?$")

    /// A copy the hub saved beside a file it could not merge: `tasks (conflict iPad 2026-11-12 0815).yaml`.
    public static func isConflictCopy(_ path: String) -> Bool {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        return conflictPattern.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
    }
}
