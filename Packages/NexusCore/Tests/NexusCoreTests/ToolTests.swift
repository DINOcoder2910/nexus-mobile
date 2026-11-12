import XCTest
@testable import NexusCore

/// Tools on boards must read and write what the laptop's renderer/src/tools/catalog.js and boardtools.js do.
final class ToolTests: XCTestCase {
    func testSrcIsReadAsTheLaptopReadsIt() {
        XCTAssertEqual(ToolCatalog.parseSrc("nexus:tool/molecules"), .builtin("molecules"))
        XCTAssertNil(ToolCatalog.parseSrc("nexus:tool/../x"))
        XCTAssertNil(ToolCatalog.parseSrc("nexus:tool/Bad Name"))
        XCTAssertEqual(ToolCatalog.parseSrc("../Titration.html"), .file("../Titration.html"))
        XCTAssertEqual(ToolCatalog.parseSrc("files/a.HTM"), .file("files/a.HTM"))
        XCTAssertNil(ToolCatalog.parseSrc("https://example.com/a.html"))
        XCTAssertNil(ToolCatalog.parseSrc("/etc/a.html"))
        XCTAssertNil(ToolCatalog.parseSrc("a\\b.html"))
        XCTAssertNil(ToolCatalog.parseSrc("notes.md"))
        XCTAssertNil(ToolCatalog.parseSrc(nil))
    }

    func testTitles() {
        XCTAssertEqual(ToolCatalog.title("nexus:tool/vsepr"), "VSEPR chart")
        XCTAssertEqual(ToolCatalog.title("nexus:tool/other"), "other")
        XCTAssertEqual(ToolCatalog.title("../Lab/Titration curve.html"), "Titration curve")
        XCTAssertEqual(ToolCatalog.title("x.md"), "Tool")
    }

    func testPageURLStaysInTheDataFolder() {
        let root = URL(fileURLWithPath: "/data")
        let board = root.appendingPathComponent("notebooks/Chem/Redox/Cells.board")
        XCTAssertEqual(ToolCatalog.pageURL("nexus:tool/enthalpies", board: board, root: root)?.path, "/data/.nexus-tools/enthalpies.html")
        XCTAssertNil(ToolCatalog.pageURL("nexus:tool/unknown", board: board, root: root))
        XCTAssertEqual(ToolCatalog.pageURL("../Titration.html", board: board, root: root)?.path, "/data/notebooks/Chem/Redox/Titration.html")
        XCTAssertNil(ToolCatalog.pageURL("../../../../../x.html", board: board, root: root))
    }

    func testStateIsAnObjectThatFits() throws {
        XCTAssertNil(ToolCatalog.keepState(nil))
        XCTAssertNil(ToolCatalog.keepState(.array([])))
        XCTAssertNil(ToolCatalog.keepState(.string("x")))
        let small = try JSONValue.parse("{\"vsepr\":{\"bp\":3,\"lp\":1}}")
        XCTAssertEqual(ToolCatalog.keepState(small), small)
        let big = JSONValue.object([("s", .string(String(repeating: "a", count: ToolCatalog.stateMax)))])
        XCTAssertNil(ToolCatalog.keepState(big))
    }

    func testMessagesAreChecked() {
        XCTAssertEqual(ToolCatalog.message("{\"nexus\":\"tool\",\"type\":\"ready\"}"), .ready)
        XCTAssertEqual(ToolCatalog.message("{\"nexus\":\"tool\",\"type\":\"state\",\"state\":{\"a\":1}}"), .state(.object([("a", .number(1))])))
        XCTAssertNil(ToolCatalog.message("{\"nexus\":\"tool\",\"type\":\"state\",\"state\":[1]}"))
        XCTAssertEqual(ToolCatalog.message("{\"nexus\":\"tool\",\"type\":\"size\",\"h\":12}"), .size(80))
        XCTAssertEqual(ToolCatalog.message("{\"nexus\":\"tool\",\"type\":\"size\",\"h\":9000}"), .size(4000))
        XCTAssertNil(ToolCatalog.message("{\"type\":\"ready\"}"))
        XCTAssertNil(ToolCatalog.message("{\"nexus\":\"tool\",\"type\":\"init\"}"))
        XCTAssertNil(ToolCatalog.message("not json"))
    }

    func testInitScript() {
        XCTAssertEqual(ToolCatalog.initScript(state: nil, dark: false),
                       "window.postMessage({\"nexus\":\"tool\",\"type\":\"init\",\"state\":null,\"theme\":{\"dark\":false,\"vars\":{}}}, '*'); true;")
        let s = ToolCatalog.initScript(state: .object([("t", .string("a\u{2028}b"))]), dark: true)
        XCTAssertTrue(s.contains("a\\u2028b"))
        XCTAssertTrue(s.contains("\"dark\":true"))
    }

    /// The same line the laptop's addToolItem writes for a card.
    func testNewItemIsWhatTheLaptopWrites() {
        let live = ToolCatalog.item(id: "abc12", src: "nexus:tool/molecules", x: 10.4, y: 20.6)
        XCTAssertEqual(live.json.text, "{\"id\":\"abc12\",\"type\":\"tool\",\"x\":10,\"y\":21,\"w\":760,\"h\":650,\"src\":\"nexus:tool/molecules\",\"show\":\"live\"}")
        let pic = ToolCatalog.item(id: "abc13", src: "../T.html", x: 0, y: 0, w: 300, h: 200, image: "files/T.png", state: .object([("k", .number(1))]))
        XCTAssertEqual(pic.json.text, "{\"id\":\"abc13\",\"type\":\"tool\",\"x\":0,\"y\":0,\"w\":300,\"h\":230,\"src\":\"../T.html\",\"show\":\"picture\",\"image\":\"files/T.png\",\"state\":{\"k\":1}}")
        XCTAssertFalse(pic.isForeign)
    }

    func testIndexAndNotebookFolders() {
        XCTAssertEqual(ToolCatalog.readIndex("{\"format\":\"nexus-tools/1\",\"version\":\"7\",\"tools\":[{\"name\":\"molecules\",\"title\":\"Molecules\",\"file\":\"molecules.html\"}]}"), ["molecules"])
        XCTAssertNil(ToolCatalog.readIndex("{\"format\":\"other\"}"))
        XCTAssertNil(ToolCatalog.readIndex(nil))
        XCTAssertEqual(ToolCatalog.notebookDirs(boardPath: "notebooks/Chem/Redox/Cells.board"), ["notebooks/Chem/Redox", "notebooks/Chem"])
        XCTAssertEqual(ToolCatalog.notebookDirs(boardPath: "notebooks/Chem/Cells.board"), ["notebooks/Chem"])
        XCTAssertEqual(ToolCatalog.notebookDirs(boardPath: "Loose.board"), [""])
        XCTAssertEqual(ToolCatalog.relative("notebooks/Chem/Redox/T.html", fromBoard: "notebooks/Chem/Redox/Cells.board"), "../T.html")
        XCTAssertEqual(ToolCatalog.relative("notebooks/Chem/T.html", fromBoard: "notebooks/Chem/Redox/Cells.board"), "../../T.html")
    }

    /// A board with the tool feature opens for editing, and its tool items are this app's own.
    func testToolFeatureIsKnown() throws {
        XCTAssertEqual(BoardFormat.unknownFeatures(try JSONValue.parse("{\"features\":[\"tool\"]}")), [])
        XCTAssertTrue(BoardFormat.itemTypes.contains("tool"))
    }

    /// The laptop's built tools reach the iPad: sync doesn't skip .nexus-tools (only .nexus).
    func testBuiltToolsSync() {
        XCTAssertFalse(SyncPaths.isIgnored(".nexus-tools/molecules.html"))
        XCTAssertFalse(SyncPaths.isIgnored(".nexus-tools/tools.json"))
    }
}
