import Foundation

/// A board's paper (board.json `"paper": {"kind": "dots", "size": 24}`, nexus docs/data-format.md "Paper"), and what of its pattern
/// to draw for the part of the board on screen. The same rules as the laptop's `renderer/src/board/paper.js` (one test table).
///
/// The pattern is in board units, so it zooms like the writing. Zoomed far out it thins to every 4th line, then every 16th, and
/// fades away rather than turning into grey noise.
public struct Paper: Equatable {
    public enum Kind: String, CaseIterable { case plain, dots, grid, lined, graph }

    public var kind: Kind
    public var size: Double

    public init(kind: Kind, size: Double? = nil) {
        self.kind = kind
        self.size = size ?? Paper.defaultSize(kind)
    }

    public static let plain = Paper(kind: .plain)

    /// The spacing choices offered for each kind (the first is the default).
    public static func sizes(_ kind: Kind) -> [Double] {
        switch kind {
        case .plain: return []
        case .dots, .grid: return [24, 32, 40]
        case .lined: return [34, 28, 42]
        case .graph: return [8]
        }
    }

    public static func defaultSize(_ kind: Kind) -> Double { sizes(kind).first ?? 24 }

    /// From board.json's `paper` (missing, unknown or broken = plain; a silly size = the kind's default).
    public init(_ v: JSONValue?) {
        let kind = Kind(rawValue: v?["kind"]?.string ?? "") ?? .plain
        var size = v?["size"]?.number ?? Paper.defaultSize(kind)
        if !(size >= 4 && size <= 400) { size = Paper.defaultSize(kind) }
        self.init(kind: kind, size: size)
    }

    /// As board.json writes it; nil for plain paper (the field is left out).
    public var json: JSONValue? {
        kind == .plain ? nil : .object([("kind", .string(kind.rawValue)), ("size", .number(size))])
    }

    /// What to draw over `visible` (board units) at `zoom` (screen points per unit).
    public struct Pattern: Equatable {
        /// x of each vertical line, y of each horizontal line (board units); dots sit where they cross.
        public var xs: [Double] = []
        public var ys: [Double] = []
        public var dots = false
        /// Lines drawn stronger (graph paper's every fifth), as indexes into xs and ys.
        public var strongX: Set<Int> = []
        public var strongY: Set<Int> = []
        /// 0 (not drawn) to 1.
        public var alpha: Double = 0
    }

    /// Lines or dots closer than this on screen thin out (every 4th, then every 16th).
    public static let minGap: Double = 10

    public func pattern(visible r: (x: Double, y: Double, w: Double, h: Double), zoom: Double) -> Pattern {
        var p = Pattern()
        guard kind != .plain, size > 0, zoom > 0, r.w > 0, r.h > 0 else { return p }
        var step = 1.0
        while size * step * zoom < Paper.minGap && step < 16 { step *= 4 }
        let gap = size * step * zoom // on screen
        // at the coarsest step it fades out between 16 and 10 points apart, so the paper goes quietly when zoomed far out
        p.alpha = step >= 16 ? max(0, min(1, (gap - Paper.minGap) / 6)) : 1
        if p.alpha <= 0 { p.alpha = 0; return p }
        let s = size * step
        func marks(_ from: Double, _ len: Double) -> [Double] {
            let first = (from / s).rounded(.up), last = ((from + len) / s).rounded(.down)
            guard last >= first, last - first < 2000 else { return [] }
            return stride(from: first, through: last, by: 1).map { $0 * s }
        }
        switch kind {
        case .plain: break
        case .lined: p.ys = marks(r.y, r.h)
        case .dots: p.xs = marks(r.x, r.w); p.ys = marks(r.y, r.h); p.dots = true
        case .grid: p.xs = marks(r.x, r.w); p.ys = marks(r.y, r.h)
        case .graph:
            p.xs = marks(r.x, r.w); p.ys = marks(r.y, r.h)
            let every = 5 * s
            func strong(_ v: [Double]) -> Set<Int> {
                Set(v.indices.filter { abs(v[$0] / every - (v[$0] / every).rounded()) < 1e-9 })
            }
            p.strongX = strong(p.xs); p.strongY = strong(p.ys)
        }
        return p
    }

    /// The nearest pattern line to `y` (for Insert space and shapes snapping to the background); `y` itself on plain paper.
    public func snap(_ y: Double) -> Double {
        guard kind != .plain, size > 0 else { return y }
        return (y / size).rounded() * size
    }
}
