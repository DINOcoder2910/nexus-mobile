import Foundation

/// The Insert space tool's options and the pure parts of what it does (the approved board redesign, "Insert space"): which way the
/// room goes, how much, and which things move when only one column moves. Board units throughout.
public enum InsertSpace {
    /// What moves: everything past the line, or only the column (or, sideways, the row) you started in.
    public enum Moves: String, CaseIterable { case everything, column }
    /// Which way: down (or up to close) only, or follow the drag (sideways makes room to the right, for a margin column).
    public enum Direction: String, CaseIterable { case follow, down }
    /// How much: whole lines or squares of the background, or exactly the drag.
    public enum Size: String, CaseIterable { case snap, free }
    /// Closing space: never piles things on top of each other, or exactly the drag.
    public enum Closing: String, CaseIterable { case stopAtContent, free }
    /// A tap without dragging adds this much.
    public enum Tap: String, CaseIterable { case half, threeLines, full, nothing }
    /// After one use: back to the pen you had, or stay on Insert space.
    public enum After: String, CaseIterable { case pen, stay }

    /// A thing on the board, as a box.
    public struct Box: Equatable {
        public var minX, minY, maxX, maxY: Double
        public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
            self.minX = minX; self.minY = minY; self.maxX = maxX; self.maxY = maxY
        }
    }

    /// Sideways when the drag goes more across than down, and the option lets it.
    public static func sideways(dx: Double, dy: Double, direction: Direction) -> Bool {
        direction == .follow && abs(dx) > abs(dy)
    }

    /// The space a drag of `by` makes: whole steps of the paper's spacing when snapping on a patterned paper (lined paper has no
    /// columns, so sideways it stays free), else the drag itself, rounded.
    public static func amount(_ by: Double, paper: Paper, size: Size, sideways: Bool = false) -> Double {
        guard size == .snap, paper.kind != .plain, paper.size > 0, !(sideways && paper.kind == .lined) else { return by.rounded() }
        return (by / paper.size).rounded() * paper.size
    }

    /// Where the line goes when you put the Pencil down at `at`: on the nearest line of the paper when snapping.
    public static func line(_ at: Double, paper: Paper, size: Size, sideways: Bool = false) -> Double {
        guard size == .snap, !(sideways && paper.kind == .lined) else { return at }
        return paper.snap(at)
    }

    /// What a tap adds, for a screen `screen` units tall; 0 for Nothing.
    public static func tapAmount(_ tap: Tap, screen: Double, paper: Paper, size: Size) -> Double {
        let lineHeight = paper.kind == .plain ? 32 : paper.size
        let raw: Double
        switch tap {
        case .half: raw = screen / 2
        case .threeLines: return 3 * lineHeight
        case .full: raw = screen
        case .nothing: return 0
        }
        let a = amount(raw, paper: paper, size: size)
        return a >= 1 ? a : raw.rounded()
    }

    /// The column you started in, across (`lo`...`hi`): it grows from `seed` over everything near or past the line that overlaps
    /// it, until nothing more does. Things more than `reach` before the line don't count, so a wide title far above doesn't make
    /// the whole board one column. Sideways, read x as y: the row you started in. Nil when nothing is there.
    public static func band(seed: Double, line: Double, boxes: [Box], sideways: Bool = false, reach: Double = 400) -> ClosedRange<Double>? {
        // (start, end) across the drag, (lo, hi) along it
        let spans = boxes.map { b in sideways ? (across: (b.minY, b.maxY), along: (b.minX, b.maxX)) : (across: (b.minX, b.maxX), along: (b.minY, b.maxY)) }
            .filter { $0.along.1 >= line - reach }
        var lo = seed, hi = seed
        var used = Array(repeating: false, count: spans.count)
        var grew = true
        var any = false
        while grew {
            grew = false
            for (i, s) in spans.enumerated() where !used[i] && s.across.1 >= lo && s.across.0 <= hi {
                used[i] = true
                any = true
                if s.across.0 < lo { lo = s.across.0; grew = true }
                if s.across.1 > hi { hi = s.across.1; grew = true }
            }
        }
        return any ? lo...hi : nil
    }

    /// True when a thing whose box is `b` moves for room at `line`: it starts at or past the line and (with a band) lies in it.
    public static func moves(_ b: Box, line: Double, sideways: Bool = false, band: ClosedRange<Double>? = nil) -> Bool {
        let start = sideways ? b.minX : b.minY
        guard line <= start else { return false }
        guard let band else { return true }
        let (lo, hi) = sideways ? (b.minY, b.maxY) : (b.minX, b.maxX)
        return hi >= band.lowerBound && lo <= band.upperBound
    }
}
