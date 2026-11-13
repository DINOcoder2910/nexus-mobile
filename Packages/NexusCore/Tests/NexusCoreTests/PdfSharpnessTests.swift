import XCTest
@testable import NexusCore

/// How sharp PDF pages are drawn: deep zoom must settle (a page drawn once counts as done), whole pages stay small, and the close-up
/// covers only what's on screen (Nov 13 2026: zoomed-in pages went grey and stayed grey on the iPad).
final class PdfSharpnessTests: XCTestCase {
    let w = 820.0, h = 1061.0 // a letter page at the printout's usual width

    func testDeepZoomSettles() {
        // the old rule asked for zoom 3 x screen 2 = 6, capped the picture under that, and so redrew it on every move
        for zoom in [1.0, 1.5, 2, 3, 5] {
            let want = PdfSharpness.pageScale(zoom: zoom, screenScale: 2, w: w, h: h)
            XCTAssertFalse(PdfSharpness.needsRedraw(have: want, want: want), "zoom \(zoom)")
            XCTAssertLessThanOrEqual(w * want * h * want, PdfSharpness.pagePixels + 1)
        }
        XCTAssertEqual(PdfSharpness.pageScale(zoom: 5, screenScale: 2, w: w, h: h), PdfSharpness.pageScale(zoom: 1.5, screenScale: 2, w: w, h: h))
    }

    func testRedrawRules() {
        XCTAssertTrue(PdfSharpness.needsRedraw(have: 0, want: 2))   // not drawn (or the draw failed)
        XCTAssertTrue(PdfSharpness.needsRedraw(have: 1, want: 2))   // zoomed in: too blurry
        XCTAssertFalse(PdfSharpness.needsRedraw(have: 1.9, want: 2))
        XCTAssertFalse(PdfSharpness.needsRedraw(have: 3, want: 2))  // zoomed out a little: keep it
        XCTAssertTrue(PdfSharpness.needsRedraw(have: 3, want: 0.5)) // zoomed well out: give the memory back
        // zoomed far out, a page is a small picture
        XCTAssertEqual(PdfSharpness.pageScale(zoom: 0.2, screenScale: 2, w: w, h: h), 0.5)
    }

    func testCloseUpOnlyPastThePagePicture() {
        let seg = (x: 0.0, y: 0.0, w: w, h: h)
        let have = PdfSharpness.pageScale(zoom: 1.5, screenScale: 2, w: w, h: h)
        XCTAssertNil(PdfSharpness.closeUp(segment: seg, visible: (0, 0, 800, 560), zoom: 1.4, screenScale: 2, pageHave: have))
        // at 500 %: a 1194 x 834 screen shows 239 x 167 board units; the close-up is that and a margin, at full sharpness
        let vis = (x: 300.0, y: 400.0, w: 238.8, h: 166.8)
        guard let c = PdfSharpness.closeUp(segment: seg, visible: vis, zoom: 5, screenScale: 2, pageHave: have) else { return XCTFail("no close-up") }
        XCTAssertEqual(c.scale, 10)
        XCTAssertEqual(c.rect.x, 300 - 23.88, accuracy: 0.001)
        XCTAssertEqual(c.rect.w, 238.8 * 1.2, accuracy: 0.001)
        XCTAssertLessThanOrEqual(c.rect.w * c.scale * c.rect.h * c.scale, PdfSharpness.closeUpPixels + 1)
    }

    func testCloseUpStaysOnItsPage() {
        let seg = (x: 0.0, y: 0.0, w: w, h: h)
        let have = 2.0
        // the view straddles the page's bottom edge: only the page's part
        let c = PdfSharpness.closeUp(segment: seg, visible: (100, 1000, 240, 170), zoom: 5, screenScale: 2, pageHave: have)
        XCTAssertEqual(c?.rect.y ?? 0, 1000 - 17, accuracy: 0.001)
        XCTAssertEqual((c?.rect.y ?? 0) + (c?.rect.h ?? 0), h, accuracy: 0.001)
        // off the page: none
        XCTAssertNil(PdfSharpness.closeUp(segment: seg, visible: (100, 1300, 240, 170), zoom: 5, screenScale: 2, pageHave: have))
    }
}
