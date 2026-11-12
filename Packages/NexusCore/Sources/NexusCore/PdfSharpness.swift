import Foundation

/// How sharp a PDF printout's pages are drawn on a board (Sources/Boards/BoardItemViews.swift `PdfPrintout`).
///
/// Each page is one picture at a sensible size: sharp up to 150 % zoom and never more than `pagePixels`. Closer than that, a
/// close-up picture of just the part of the page on screen is drawn on top at full sharpness. Before Nov 13 2026 a page was one
/// picture up to 16 million pixels: at deep zoom it never counted as sharp enough (the size cap kept it under the mark), so it was
/// drawn again on every move until the iPad ran short of memory and a page came back blank, then stayed blank.
public enum PdfSharpness {
    /// Most pixels in one whole-page picture (about 32 MB).
    public static let pagePixels: Double = 8_000_000
    /// Most pixels in one close-up picture: a screen and a margin.
    public static let closeUpPixels: Double = 9_000_000
    /// The zoom up to which a whole-page picture is sharp; past it the close-up takes over.
    public static let pageZoom: Double = 1.5

    /// The pixels per board unit a whole-page picture should have at `zoom`, for a page `w` x `h` board units.
    public static func pageScale(zoom: Double, screenScale: Double, w: Double, h: Double) -> Double {
        let want = min(max(zoom, 0.25), pageZoom) * screenScale
        let cap = (pagePixels / max(1, w * h)).squareRoot()
        return min(want, cap)
    }

    /// Whether a page drawn at `have` pixels per unit (0: not drawn) should be drawn again for `want`: too blurry, or far sharper
    /// than needed (zoomed well out), so the memory is given back. `want` is what `pageScale` gives, so a page drawn at it is done.
    public static func needsRedraw(have: Double, want: Double) -> Bool {
        have <= 0 || have < want * 0.85 || have > want * 2.5
    }

    /// The close-up for one piece of a page: the part of `segment` (x, y, w, h on the board) in view, with a margin so a small move
    /// doesn't show its edge, and its pixels per unit. Nil when the whole-page picture (`pageHave`) is sharp enough.
    public static func closeUp(segment: (x: Double, y: Double, w: Double, h: Double), visible: (x: Double, y: Double, w: Double, h: Double),
                               zoom: Double, screenScale: Double, pageHave: Double) -> (rect: (x: Double, y: Double, w: Double, h: Double), scale: Double)? {
        let want = zoom * screenScale
        guard want > pageHave * 1.1 else { return nil }
        let mx = visible.w * 0.1, my = visible.h * 0.1
        let x0 = max(segment.x, visible.x - mx), y0 = max(segment.y, visible.y - my)
        let x1 = min(segment.x + segment.w, visible.x + visible.w + mx), y1 = min(segment.y + segment.h, visible.y + visible.h + my)
        guard x1 > x0, y1 > y0 else { return nil }
        let w = x1 - x0, h = y1 - y0
        let scale = min(want, (closeUpPixels / (w * h)).squareRoot())
        guard scale > pageHave * 1.1 else { return nil }
        return ((x0, y0, w, h), scale)
    }
}
