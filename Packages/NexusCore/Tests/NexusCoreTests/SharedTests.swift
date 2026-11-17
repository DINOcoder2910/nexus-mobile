import XCTest
@testable import NexusCore

/// Sharing into Nexus (Save to Nexus): what a shared thing is and where it lands.
final class SharedTests: XCTestCase {
    func testKinds() {
        XCTAssertEqual(Shared.kind(typeId: "com.adobe.pdf", name: "file.pdf", data: Data("%PDF-1.7".utf8)), .pdf)
        XCTAssertEqual(Shared.kind(typeId: nil, name: "handout", data: Data("%PDF-1.4 …".utf8)), .pdf)
        XCTAssertEqual(Shared.kind(typeId: "public.heic", name: "IMG_0412.HEIC", data: Data([0, 1, 2])), .image)
        XCTAssertEqual(Shared.kind(typeId: nil, name: "photo.JPG", data: Data([0xFF, 0xD8])), .image)
        XCTAssertEqual(Shared.kind(typeId: "public.url", name: "link", data: Data("https://example.com/a#b".utf8)), .link("https://example.com/a#b"))
        XCTAssertEqual(Shared.kind(typeId: "public.plain-text", name: "text.txt", data: Data("Buy  milk\nand eggs".utf8)), .text("Buy  milk\nand eggs"))
        XCTAssertEqual(Shared.kind(typeId: "public.mpeg-4", name: "clip.mp4", data: Data([0, 0, 0, 0x18])), .unknown)
        XCTAssertEqual(Shared.kind(typeId: "public.plain-text", name: "empty.txt", data: Data("  \n".utf8)), .unknown)
    }

    func testLinkFiles() throws {
        let plist = try PropertyListSerialization.data(fromPropertyList: ["URL": "https://apple.com"], format: .binary, options: 0)
        XCTAssertEqual(Shared.kind(typeId: "com.apple.web-internet-location", name: "Apple.webloc", data: plist), .link("https://apple.com"))
        let win = "[InternetShortcut]\r\nURL=https://ibo.org/\r\n"
        XCTAssertEqual(Shared.kind(typeId: nil, name: "IBO.url", data: Data(win.utf8)), .link("https://ibo.org/"))
        // words with an address in them stay words
        XCTAssertEqual(Shared.kind(text: "read https://ibo.org later"), .text("read https://ibo.org later"))
        XCTAssertEqual(Shared.kind(text: "ftp://old.example"), .text("ftp://old.example"))
    }

    func testWebPages() {
        let page = #"<html><head><title>Redox &amp; you</title><link rel="canonical" href="https://chem.example/redox"></head></html>"#
        XCTAssertEqual(Shared.kind(typeId: "public.html", name: "redox.html", data: Data(page.utf8)), .link("https://chem.example/redox"))
        XCTAssertEqual(Shared.pageTitle(page), "Redox & you")
        let bare = "<html><title>Only a title</title></html>"
        XCTAssertEqual(Shared.kind(typeId: "public.html", name: "page.html", data: Data(bare.utf8)), .text("Only a title"))
    }

    func testTasks() {
        XCTAssertEqual(Shared.task(.link("https://a.com"))?.title, "https://a.com")
        XCTAssertNil(Shared.task(.link("https://a.com"))?.note)
        let titled = Shared.task(.link("https://a.com"), pageTitle: "A page\n")
        XCTAssertEqual(titled?.title, "A page")
        XCTAssertEqual(titled?.note, "https://a.com")
        let t = Shared.task(.text("Revise R3.2\n\nredox half equations"))
        XCTAssertEqual(t?.title, "Revise R3.2")
        XCTAssertEqual(t?.note, "redox half equations")
        let long = String(repeating: "a", count: 250)
        let cut = Shared.task(.text(long))
        XCTAssertEqual(cut?.title.count, 200)
        XCTAssertEqual(cut?.note, long)
        XCTAssertNil(Shared.task(.pdf))
    }

    func testNames() {
        XCTAssertEqual(Shared.notebook(nil), "Shared")
        XCTAssertEqual(Shared.notebook("  "), "Shared")
        XCTAssertEqual(Shared.notebook("Chem/R3: redox?"), "ChemR3 redox")
        XCTAssertEqual(Shared.boardName(fileName: "IMG_0412.HEIC", kind: .image), "IMG_0412")
        XCTAssertEqual(Shared.boardName(fileName: "file.pdf", kind: .pdf), "Shared PDF")
        XCTAssertEqual(Shared.boardName(fileName: "image.png", kind: .image), "Shared photo")
    }
}
