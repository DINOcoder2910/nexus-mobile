import PencilKit
import UIKit
import NexusCore

/// PencilKit strokes and the board files' strokes, both ways. Canvas coordinates are board coordinates plus `offset`
/// (a scroll view can't go below 0, so the canvas keeps room left of and above the board's content).
enum InkConvert {
    static func color(_ hex: String) -> UIColor {
        var s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if s.count == 6 { s += "FF" }
        guard s.count == 8, let v = UInt64(s, radix: 16) else { return .black }
        return UIColor(red: CGFloat((v >> 24) & 0xFF) / 255, green: CGFloat((v >> 16) & 0xFF) / 255,
                       blue: CGFloat((v >> 8) & 0xFF) / 255, alpha: CGFloat(v & 0xFF) / 255)
    }

    static func hex(_ c: UIColor) -> String { StrokeExport.hex(c) }

    static func inkType(_ id: String) -> PKInk.InkType { PKInk.InkType(rawValue: id) ?? .pen }

    static func r2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
    static func r3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }

    static func point(_ p: [Double], offset: CGPoint) -> PKStrokePoint {
        func f(_ i: Int, _ d: Double) -> Double { i < p.count && p[i].isFinite ? p[i] : d }
        return PKStrokePoint(location: CGPoint(x: f(0, 0) + offset.x, y: f(1, 0) + offset.y), timeOffset: f(5, 0),
                             size: CGSize(width: max(0.1, f(6, 2)), height: max(0.1, f(7, 2))), opacity: f(8, 1),
                             force: f(2, 1), azimuth: f(3, 0), altitude: f(4, .pi / 2))
    }

    /// The canvas strokes for a stored one: one, or one per kept part of a partly erased stroke.
    static func pkStrokes(_ s: BoardStroke, offset: CGPoint) -> [PKStroke] {
        let ink = PKInk(inkType(s.ink), color: color(s.color))
        let pts = s.points.map { point($0, offset: offset) }
        guard !pts.isEmpty else { return [] }
        guard let ranges = s.ranges, !ranges.isEmpty else {
            return [PKStroke(ink: ink, path: PKStrokePath(controlPoints: pts, creationDate: Date()), transform: .identity, mask: nil)]
        }
        return parts(s).map { r in
            PKStroke(ink: ink, path: PKStrokePath(controlPoints: Array(pts[r.lowerBound...r.upperBound]), creationDate: Date()), transform: .identity, mask: nil)
        }
    }

    /// The control points each kept range of a stroke covers (parametric values run over the control points' indices).
    static func parts(_ s: BoardStroke) -> [ClosedRange<Int>] {
        let n = s.points.count
        guard n > 0 else { return [] }
        return (s.ranges ?? []).compactMap { r in
            guard r.count >= 2 else { return nil }
            let lo = max(0, min(n - 1, Int(floor(min(r[0], r[1])))))
            let hi = max(lo, min(n - 1, Int(ceil(max(r[0], r[1])))))
            return lo...hi
        }
    }

    /// A canvas stroke as the files keep it: board coordinates, 2 decimals for x, y, w, h and 3 for the rest.
    static func boardStroke(_ k: PKStroke, offset: CGPoint, id: String) -> BoardStroke {
        let t = k.transform
        var points: [[Double]] = []
        points.reserveCapacity(k.path.count)
        for p in k.path {
            let loc = p.location.applying(t)
            points.append([r2(loc.x - offset.x), r2(loc.y - offset.y), r3(p.force), r3(p.azimuth), r3(p.altitude),
                           r3(p.timeOffset), r2(p.size.width), r2(p.size.height), r3(p.opacity)])
        }
        var ranges: [[Double]]?
        if k.mask != nil {
            ranges = k.maskedPathRanges.map { [r3($0.lowerBound), r3($0.upperBound)] }
        }
        return BoardStroke(id: id, ink: k.ink.inkType.rawValue, color: hex(k.ink.color), points: points, ranges: ranges)
    }

    /// What tells two strokes apart when PencilKit hands them back (its points are kept less precisely than the files'):
    /// the pen, the colour, the number of points, where it starts and ends, and the kept parts.
    static func fingerprint(_ s: BoardStroke) -> String {
        func q(_ v: Double) -> String { String(Int((v * 10).rounded())) }
        let a = s.points.first ?? [0, 0], b = s.points.last ?? [0, 0]
        var out = "\(s.ink)|\(s.color.uppercased())|\(s.points.count)|\(q(a[0])),\(q(a[1]))|\(q(b[0])),\(q(b[1]))"
        if let r = s.ranges { out += "|" + r.map { $0.map { String(Int(($0 * 100).rounded())) }.joined(separator: ":") }.joined(separator: ";") }
        return out
    }
}

/// Keeps each canvas stroke tied to its stroke id between saves, so a sync merge (which goes by id) sees an unchanged stroke as
/// unchanged and an erased part as the same stroke with fewer ranges.
final class InkLedger {
    private struct Seen { var id: String; var part: Int? }
    private var known: [String: Seen] = [:]
    private var stored: [String: BoardStroke] = [:]
    /// When each stroke new since the last `takeBorn()` was begun (PencilKit's creation date, ms), for the history log.
    private var born: [String: Double] = [:]

    func takeBorn() -> [String: Double] { defer { born = [:] }; return born }

    /// The drawing for these strokes (in drawing order), remembering which canvas stroke is which.
    func drawing(_ strokes: [BoardStroke], offset: CGPoint) -> PKDrawing {
        known = [:]; stored = [:]
        var out: [PKStroke] = []
        for s in strokes {
            stored[s.id] = s
            let pks = InkConvert.pkStrokes(s, offset: offset)
            if s.ranges?.isEmpty == false {
                for (i, k) in pks.enumerated() {
                    known[InkConvert.fingerprint(InkConvert.boardStroke(k, offset: offset, id: ""))] = Seen(id: s.id, part: i)
                }
            } else if let k = pks.first {
                known[InkConvert.fingerprint(InkConvert.boardStroke(k, offset: offset, id: ""))] = Seen(id: s.id, part: nil)
                known[InkConvert.fingerprint(s)] = Seen(id: s.id, part: nil)
            }
            out.append(contentsOf: pks)
        }
        return PKDrawing(strokes: out)
    }

    /// The strokes to write for the drawing as it is now, in drawing order. Unchanged ones are the stored ones (their file text kept);
    /// new ones get new ids not in `taken`.
    func strokes(_ drawing: PKDrawing, offset: CGPoint, taken: Set<String>) -> [BoardStroke] {
        var used = Set<String>()
        var taken = taken.union(stored.keys)
        // first pass: which parts of split strokes are still there
        var partsLeft: [String: Set<Int>] = [:]
        var converted: [(BoardStroke, Seen?, Date)] = []
        for k in drawing.strokes {
            let c = InkConvert.boardStroke(k, offset: offset, id: "")
            let seen = known[InkConvert.fingerprint(c)]
            if let seen, let part = seen.part { partsLeft[seen.id, default: []].insert(part) }
            converted.append((c, seen, k.path.creationDate))
        }
        var out: [BoardStroke] = []
        var nextKnown: [String: Seen] = [:]
        var nextStored: [String: BoardStroke] = [:]
        for (c, seen, made) in converted {
            if let seen, !used.contains(seen.id), var s = stored[seen.id] {
                used.insert(seen.id)
                if seen.part != nil {
                    // a split stroke: written once, with the parts that are left
                    let all = s.ranges ?? []
                    let left = partsLeft[seen.id] ?? []
                    if left.count != all.count {
                        s.ranges = all.enumerated().filter { left.contains($0.offset) }.map(\.element)
                    }
                    // the remaining parts keep their places in the ledger
                    let keptIdx = all.indices.filter { left.contains($0) }
                    for (i, k) in InkConvert.pkStrokes(s, offset: offset).enumerated() where i < keptIdx.count {
                        nextKnown[InkConvert.fingerprint(InkConvert.boardStroke(k, offset: offset, id: ""))] = Seen(id: s.id, part: i)
                    }
                } else {
                    nextKnown[InkConvert.fingerprint(c)] = Seen(id: s.id, part: nil)
                    nextKnown[InkConvert.fingerprint(s)] = Seen(id: s.id, part: nil)
                }
                nextStored[s.id] = s
                out.append(s)
            } else if let seen, used.contains(seen.id), seen.part != nil {
                continue // another part of a split stroke already written
            } else {
                var s = c
                s.id = BoardFormat.newId(taken: taken)
                taken.insert(s.id)
                used.insert(s.id)
                born[s.id] = (made.timeIntervalSince1970 * 1000).rounded()
                nextKnown[InkConvert.fingerprint(c)] = Seen(id: s.id, part: nil)
                nextStored[s.id] = s
                out.append(s)
            }
        }
        known = nextKnown
        stored = nextStored
        return out
    }
}
