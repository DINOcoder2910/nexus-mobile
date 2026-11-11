import PencilKit
import UIKit

/// Writes PencilKit ink as plain JSON: every stroke's pen, colour and points
/// (position, pressure, tilt, time, size). This is the data Windows Nexus would redraw from.
enum StrokeExport {
    static let pointFields = ["x", "y", "force", "azimuth", "altitude", "t", "w", "h", "opacity"]

    static func json(_ drawing: PKDrawing) -> Data? {
        let strokes: [[String: Any]] = drawing.strokes.map { stroke in
            let t = stroke.transform
            var points: [[Double]] = []
            points.reserveCapacity(stroke.path.count)
            for p in stroke.path {
                let loc = p.location.applying(t)
                points.append([round2(loc.x), round2(loc.y), round3(p.force), round3(p.azimuth), round3(p.altitude),
                               round3(CGFloat(p.timeOffset)), round2(p.size.width), round2(p.size.height), round3(p.opacity)])
            }
            return ["ink": stroke.ink.inkType.rawValue, "color": hex(stroke.ink.color), "points": points]
        }
        let obj: [String: Any] = ["format": "nexus-strokes-test/1", "pointFields": pointFields, "strokes": strokes]
        return try? JSONSerialization.data(withJSONObject: obj)
    }

    static func hex(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let c = { (v: CGFloat) in Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X%02X", c(r), c(g), c(b), c(a))
    }

    static func round2(_ v: CGFloat) -> Double { (Double(v) * 100).rounded() / 100 }
    static func round3(_ v: CGFloat) -> Double { (Double(v) * 1000).rounded() / 1000 }
}
