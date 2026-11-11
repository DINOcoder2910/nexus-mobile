import Foundation
import PencilKit

struct BoardInfo: Identifiable, Hashable {
    let id: String
    var name: String
    var pdfName: String?
    var modified: Date
}

/// Boards live in Documents/Boards/<id>/: board.json (name, PDF), ink.drawing (PencilKit),
/// strokes.json (the same ink as open data, to check the laptop can read it) and a copy of the PDF.
enum BoardStore {
    static var root: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Boards", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func folder(_ id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }

    static func list() -> [BoardInfo] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: keys) else { return [] }
        return items.compactMap { url -> BoardInfo? in
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isDirectory == true else { return nil }
            let meta = readMeta(url)
            return BoardInfo(id: url.lastPathComponent, name: meta["name"] ?? url.lastPathComponent,
                             pdfName: meta["pdf"], modified: values?.contentModificationDate ?? .distantPast)
        }.sorted { $0.modified > $1.modified }
    }

    static func readMeta(_ folder: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("board.json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var out: [String: String] = [:]
        if let n = obj["name"] as? String { out["name"] = n }
        if let p = obj["pdf"] as? String { out["pdf"] = p }
        return out
    }

    /// Where the PDF's first page sits on the board (it moves when the board grows left or up).
    static func origin(_ id: String) -> CGPoint? {
        guard let obj = readJSON(id), let x = obj["originX"] as? Double, let y = obj["originY"] as? Double else { return nil }
        return CGPoint(x: x, y: y)
    }

    static func setOrigin(_ point: CGPoint, id: String) {
        var obj = readJSON(id) ?? [:]
        obj["originX"] = Double(point.x)
        obj["originY"] = Double(point.y)
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]) {
            try? data.write(to: folder(id).appendingPathComponent("board.json"), options: .atomic)
        }
    }

    private static func readJSON(_ id: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: folder(id).appendingPathComponent("board.json")) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func create(name: String, pdf: URL?) throws -> BoardInfo {
        let id = UUID().uuidString
        let dir = folder(id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var meta: [String: Any] = ["name": name, "format": "nexus-board-test/1"]
        var pdfName: String?
        if let pdf {
            let access = pdf.startAccessingSecurityScopedResource()
            defer { if access { pdf.stopAccessingSecurityScopedResource() } }
            try FileManager.default.copyItem(at: pdf, to: dir.appendingPathComponent(pdf.lastPathComponent))
            pdfName = pdf.lastPathComponent
            meta["pdf"] = pdfName
        }
        let data = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted])
        try data.write(to: dir.appendingPathComponent("board.json"))
        return BoardInfo(id: id, name: name, pdfName: pdfName, modified: Date())
    }

    static func loadDrawing(_ id: String) -> PKDrawing {
        guard let data = try? Data(contentsOf: folder(id).appendingPathComponent("ink.drawing")),
              let drawing = try? PKDrawing(data: data) else { return PKDrawing() }
        return drawing
    }

    static func save(_ drawing: PKDrawing, id: String) {
        let dir = folder(id)
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        try? drawing.dataRepresentation().write(to: dir.appendingPathComponent("ink.drawing"), options: .atomic)
        if let json = StrokeExport.json(drawing) {
            try? json.write(to: dir.appendingPathComponent("strokes.json"), options: .atomic)
        }
    }

    static func delete(_ id: String) { try? FileManager.default.removeItem(at: folder(id)) }
}
