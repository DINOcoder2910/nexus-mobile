import Foundation

/// The files a task points at, as the laptop works them out (nexus `desktop/backend/src/plan.rs` `task_files`): `[[links]]` in its
/// title or note that lead to a file in the folder (not a note), so Next up can show them and offer Write on it for a PDF.
public enum TaskFiles {
    public struct File: Hashable {
        public var path: String
        public var name: String { (path as NSString).lastPathComponent }
        /// "pdf", "image" or "file"
        public var kind: String {
            switch (path as NSString).pathExtension.lowercased() {
            case "pdf": return "pdf"
            case "png", "jpg", "jpeg", "heic", "gif", "webp": return "image"
            default: return "file"
            }
        }
        public init(path: String) { self.path = path }
    }

    /// The link targets in a task's title and note that name a file with an extension other than .md, in order, each once
    /// ("[[files/Redox.pdf|the sheet]]" -> "files/Redox.pdf"; a "#heading" part is dropped).
    public static func targets(_ t: NexusTask) -> [String] {
        var out: [String] = []
        for text in [t.title, t.note ?? ""] {
            var rest = Substring(text)
            while let i = rest.range(of: "[[") {
                let after = rest[i.upperBound...]
                guard let j = after.range(of: "]]") else { break }
                var target = String(after[..<j.lowerBound])
                if let bar = target.firstIndex(of: "|") { target = String(target[..<bar]) }
                if let hash = target.firstIndex(of: "#") { target = String(target[..<hash]) }
                target = target.trimmingCharacters(in: .whitespaces)
                let ext = (target as NSString).pathExtension.lowercased()
                if !ext.isEmpty, ext != "md", !out.contains(target) { out.append(target) }
                rest = after[j.upperBound...]
            }
        }
        return out
    }

    /// Where a link from `file` (a task list's path in the folder) leads: beside the list first, then from the folder's top, then
    /// the first file of that name under the list's folder (`find`). nil when none is there.
    public static func resolve(_ target: String, from file: String, exists: (String) -> Bool, find: (String) -> String?) -> String? {
        let dir = (file as NSString).deletingLastPathComponent
        for c in [dir.isEmpty ? target : dir + "/" + target, target] {
            let n = normalise(c)
            if !n.isEmpty, !n.hasPrefix(".."), exists(n) { return n }
        }
        return find((target as NSString).lastPathComponent)
    }

    /// Every file a task points at that is there.
    public static func files(_ t: NexusTask, exists: (String) -> Bool, find: (String) -> String?) -> [File] {
        var seen = Set<String>()
        return targets(t).compactMap { resolve($0, from: t.file, exists: exists, find: find) }.filter { seen.insert($0).inserted }.map(File.init)
    }

    /// "a/b/../c/./d.pdf" -> "a/c/d.pdf"
    static func normalise(_ path: String) -> String {
        var parts: [String] = []
        for p in path.split(separator: "/") {
            if p == "." || p.isEmpty { continue }
            if p == "..", let last = parts.last, last != ".." { parts.removeLast() } else { parts.append(String(p)) }
        }
        return parts.joined(separator: "/")
    }
}
