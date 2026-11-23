import XCTest
@testable import NexusCore

/// A block's Google Doc link (GoogleDocLink.swift): a Doc's id from a pasted link, the header's value round trip, and what the panel
/// says (the laptop's gpanel.js `panelModel`).
final class GoogleDocLinkTests: XCTestCase {
    func testDocIdFromWhatIsPasted() {
        XCTAssertEqual(GoogleDocLink.docId("https://docs.google.com/document/d/1AbCdEfGhIjKlMn_-x/edit?tab=t.0"), "1AbCdEfGhIjKlMn_-x")
        XCTAssertEqual(GoogleDocLink.docId(" https://docs.google.com/document/u/1/d/1AbCdEfGhIjKlMn/view "), "1AbCdEfGhIjKlMn")
        XCTAssertEqual(GoogleDocLink.docId("1AbCdEfGhIjKlMn"), "1AbCdEfGhIjKlMn")
        XCTAssertNil(GoogleDocLink.docId("hello"))
        XCTAssertNil(GoogleDocLink.docId("https://example.com/doc"))
    }

    func testTitleFromTheBlocksFirstLine() {
        XCTAssertEqual(GoogleDocLink.title(from: "\n# **Redox** notes\nmore"), "Redox notes")
        XCTAssertEqual(GoogleDocLink.title(from: "- [x] a list"), "x a list")
        XCTAssertEqual(GoogleDocLink.title(from: ""), "")
    }

    func testTheHeaderValueKeepsWhatTheBridgeWrote() throws {
        let v = try JSONValue.parse(#"{"doc":"abc","url":"https://x","title":"T","tabs":{"t.0":{}}}"#)
        let g = try XCTUnwrap(GoogleDocLink(v))
        XCTAssertEqual(g.json.text, #"{"doc":"abc","url":"https://x","title":"T","tabs":{"t.0":{}}}"#)
        var e = g; e.error = "Both this block and the Doc have words. Choose which to keep."
        XCTAssertEqual(e.choosing("pull").json.text, #"{"doc":"abc","url":"https://x","title":"T","tabs":{"t.0":{}},"start":"pull"}"#)
        XCTAssertEqual(GoogleDocLink(create: true, title: "Redox").json.text, #"{"create":true,"title":"Redox"}"#)
        XCTAssertNil(GoogleDocLink(.string("x")))
    }

    func testWhatThePanelSays() throws {
        let on = GoogleHubState(state: "ok", enabled: true, connected: true)
        var p = GooglePanel.model(g: nil, hub: GoogleHubState(state: "nohub"), link: nil)
        XCTAssertEqual(p.tone, .off)
        XCTAssertEqual(p.actions, [.settings])
        p = GooglePanel.model(g: nil, hub: on, link: nil)
        XCTAssertEqual(p.head, "Not linked to a Google Doc")
        XCTAssertEqual(p.actions, [.make, .link])
        p = GooglePanel.model(g: GoogleDocLink(create: true, title: "x"), hub: on, link: nil)
        XCTAssertEqual(p.head, "Making the Doc…")
        XCTAssertEqual(p.actions, [.unlink])
        var both = GoogleDocLink(doc: "a"); both.error = GooglePanel.bothWords
        XCTAssertEqual(GooglePanel.model(g: both, hub: on, link: nil).actions, [.push, .pull, .unlink])
        let now = Date()
        let iso = ISO8601DateFormatter().string(from: now.addingTimeInterval(-180))
        let round = GoogleLinkRound(try JSONValue.parse("{\"path\":\"a\",\"state\":\"ok\",\"at\":\"\(iso)\",\"tabs\":2}"))
        XCTAssertEqual(round?.tabs, 2)
        let linked = GoogleDocLink(try JSONValue.parse(#"{"doc":"a","url":"https://docs.google.com/document/d/a/edit","title":"Redox"}"#))
        p = GooglePanel.model(g: linked, hub: on, link: round, now: now)
        XCTAssertEqual(p.head, "Redox")
        XCTAssertEqual(p.lines.first, "In step. Last checked 3 minutes ago.")
        XCTAssertEqual(p.actions, [.open, .sync, .unlink])
        let status = GoogleHubState(status: try JSONValue.parse(#"{"enabled":true,"connected":false,"label":null,"links":[]}"#))
        XCTAssertEqual(GooglePanel.model(g: linked, hub: status, link: nil).actions, [.settings, .open, .unlink])
    }
}
