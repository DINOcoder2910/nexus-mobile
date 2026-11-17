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

    /// The same fingerprint straight from a canvas stroke, without turning all its points into the files' form (that made every save
    /// on a big board convert every stroke on it): only the first and last point, rounded as `boardStroke` rounds them.
    static func fingerprint(_ k: PKStroke, offset: CGPoint) -> String {
        let path = k.path
        let n = path.count
        func q(_ v: Double) -> String { String(Int((v * 10).rounded())) }
        func xy(_ i: Int) -> (Double, Double) {
            guard n > 0 else { return (0, 0) }
            let loc = path[i].location.applying(k.transform)
            return (r2(loc.x - offset.x), r2(loc.y - offset.y))
        }
        let a = xy(0), b = xy(max(0, n - 1))
        var out = "\(k.ink.inkType.rawValue)|\(hex(k.ink.color).uppercased())|\(n)|\(q(a.0)),\(q(a.1))|\(q(b.0)),\(q(b.1))"
        if k.mask != nil {
            out += "|" + k.maskedPathRanges.map { "\(Int((r3($0.lowerBound) * 100).rounded())):\(Int((r3($0.upperBound) * 100).rounded()))" }.joined(separator: ";")
        }
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

    /// After `strokes(_:offset:taken:)`: which stroke of the files each canvas stroke is (in the drawing's order), so Insert space
    /// can show the canvas's own strokes moving without making them again.
    private(set) var lastIds: [String] = []

    /// The fingerprints of each split stroke's parts on the canvas, by stroke id, so a save that didn't erase from it needn't make them again.
    private var partPrints: [String: [String]] = [:]

    /// The drawing for these strokes (in drawing order), remembering which canvas stroke is which.
    func drawing(_ strokes: [BoardStroke], offset: CGPoint) -> PKDrawing {
        known = [:]; stored = [:]; partPrints = [:]
        var out: [PKStroke] = []
        for s in strokes {
            stored[s.id] = s
            let pks = InkConvert.pkStrokes(s, offset: offset)
            if s.ranges?.isEmpty == false {
                var prints: [String] = []
                for (i, k) in pks.enumerated() {
                    let fp = InkConvert.fingerprint(k, offset: offset)
                    known[fp] = Seen(id: s.id, part: i)
                    prints.append(fp)
                }
                partPrints[s.id] = prints
            } else if let k = pks.first {
                known[InkConvert.fingerprint(k, offset: offset)] = Seen(id: s.id, part: nil)
                known[InkConvert.fingerprint(s)] = Seen(id: s.id, part: nil)
            }
            out.append(contentsOf: pks)
        }
        return PKDrawing(strokes: out)
    }

    /// The strokes to write for the drawing as it is now, in drawing order. Unchanged ones are the stored ones (their file text kept);
    /// new ones get new ids not in `taken`. Only new strokes are turned into the files' form: the others are told apart by their
    /// fingerprints (this runs on the main thread 600 ms after every stroke, so it must not grow with the board).
    func strokes(_ drawing: PKDrawing, offset: CGPoint, taken: Set<String>) -> [BoardStroke] {
        var used = Set<String>()
        var taken = taken.union(stored.keys)
        // first pass: which parts of split strokes are still there
        var partsLeft: [String: Set<Int>] = [:]
        var seenAll: [(PKStroke, String, Seen?)] = []
        seenAll.reserveCapacity(drawing.strokes.count)
        for k in drawing.strokes {
            let fp = InkConvert.fingerprint(k, offset: offset)
            let seen = known[fp]
            if let seen, let part = seen.part { partsLeft[seen.id, default: []].insert(part) }
            seenAll.append((k, fp, seen))
        }
        var out: [BoardStroke] = []
        var ids: [String] = []
        ids.reserveCapacity(seenAll.count)
        var nextKnown: [String: Seen] = [:]
        var nextStored: [String: BoardStroke] = [:]
        var nextParts: [String: [String]] = [:]
        for (k, fp, seen) in seenAll {
            if let seen, !used.contains(seen.id), var s = stored[seen.id] {
                used.insert(seen.id)
                if seen.part != nil {
                    // a split stroke: written once, with the parts that are left
                    let all = s.ranges ?? []
                    let left = partsLeft[seen.id] ?? []
                    if left.count != all.count {
                        s.ranges = all.enumerated().filter { left.contains($0.offset) }.map(\.element)
                        // the remaining parts keep their places in the ledger
                        let keptIdx = all.indices.filter { left.contains($0) }
                        var prints: [String] = []
                        for (i, pk) in InkConvert.pkStrokes(s, offset: offset).enumerated() where i < keptIdx.count {
                            let p = InkConvert.fingerprint(pk, offset: offset)
                            nextKnown[p] = Seen(id: s.id, part: i)
                            prints.append(p)
                        }
                        nextParts[s.id] = prints
                    } else if let prints = partPrints[s.id] {
                        for (i, p) in prints.enumerated() { nextKnown[p] = Seen(id: s.id, part: i) }
                        nextParts[s.id] = prints
                    }
                } else {
                    nextKnown[fp] = Seen(id: s.id, part: nil)
                    nextKnown[InkConvert.fingerprint(s)] = Seen(id: s.id, part: nil)
                }
                nextStored[s.id] = s
                out.append(s)
                ids.append(s.id)
            } else if let seen, used.contains(seen.id), seen.part != nil {
                ids.append(seen.id)
                continue // another part of a split stroke already written
            } else {
                var s = InkConvert.boardStroke(k, offset: offset, id: "")
                s.id = BoardFormat.newId(taken: taken)
                taken.insert(s.id)
                used.insert(s.id)
                born[s.id] = (k.path.creationDate.timeIntervalSince1970 * 1000).rounded()
                nextKnown[fp] = Seen(id: s.id, part: nil)
                nextStored[s.id] = s
                out.append(s)
                ids.append(s.id)
            }
        }
        lastIds = ids
        known = nextKnown
        stored = nextStored
        partPrints = nextParts
        return out
    }
}
