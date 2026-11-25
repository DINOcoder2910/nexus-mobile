import Foundation

/// The subjects' IB data booklets (maths: the formula booklet), opened beside a question of the question bank and on its board when
/// solving it: the laptop's `booklet_of` / `bankBooklets` (nexus desktop/backend/src/bank.rs). A booklet is a PDF in the subject's
/// folder named "data booklet" or "formula(e) booklet" (any case; spaces, dashes or underscores between, "databooklet" too); the one
/// nearest the subject's folder wins, then the newest by name (v1.1 over v1.0). The laptop looks through every file of the subject;
/// here only the subject's folder and its `files/` are read (where the booklets are), so a big sheets folder isn't walked.
public enum Booklets {
    public struct Booklet: Hashable, Identifiable {
        /// the subject (workstream id)
        public var id: String
        /// the subject's name ("Physics HL")
        public var name: String
        /// relative to the data folder
        public var path: String
        /// "Data booklet", or "Formula booklet" for maths
        public var title: String
    }

    public static func isBooklet(_ path: String) -> Bool {
        let n = ((path as NSString).lastPathComponent).lowercased()
        guard n.hasSuffix(".pdf"), !path.contains(".board/") else { return false }
        let w = " " + n.map { $0.isLetter || $0.isNumber ? String($0) : " " }.joined().split(separator: " ").joined(separator: " ") + " "
        return [" data booklet ", " databooklet ", " formula booklet ", " formulae booklet ", " formulas booklet "].contains { w.contains($0) }
    }

    /// the subject's booklet among its files (relative paths)
    public static func pick(_ files: [String]) -> String? {
        files.filter(isBooklet).sorted { a, b in
            let da = a.filter { $0 == "/" }.count, db = b.filter { $0 == "/" }.count
            return da != db ? da < db : a.lowercased() > b.lowercased()
        }.first
    }

    /// every subject's booklet, the subject `first`'s first, then by name
    public static func find(root: URL, workstreams: [Workstream], first: String?) -> [Booklet] {
        var out: [(Bool, String, Booklet)] = []
        for w in workstreams where !w.folder.isEmpty {
            var files: [String] = []
            for sub in [w.folder, w.folder + "/files"] {
                let names = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(sub).path)) ?? []
                files += names.map { sub + "/" + $0 }
            }
            guard let p = pick(files) else { continue }
            let maths = w.name.lowercased().contains("math")
            out.append((w.id == first, w.name.lowercased(), Booklet(id: w.id, name: w.name, path: p, title: maths ? "Formula booklet" : "Data booklet")))
        }
        return out.sorted { $0.0 != $1.0 ? $0.0 : $0.1 < $1.1 }.map(\.2)
    }
}
