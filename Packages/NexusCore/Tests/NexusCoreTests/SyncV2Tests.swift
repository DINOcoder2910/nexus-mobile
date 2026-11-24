import XCTest
@testable import NexusCore

/// What the Rust hub adds (the Nexus repo's docs/sync.md "The Rust hub"): op ids on writes, the change feed, and the sync chip's
/// count of what waits here while offline. Against FakeHub with its v2 features on.
final class SyncV2Tests: SyncTests {
    // (SyncTests' own tests run again under this class too: the same client must still sync with a v2 hub)
    override func setUpWithError() throws {
        try super.setUpWithError()
        hub.features = ["feed", "ops", "ifhash", "backup", "activity"]
    }

    func testHelloReadsV2AndANodeHubHasNone() throws {
        let rust = #"{"hub":"nexus-hub","protocol":1,"folderId":"f","seq":3,"v2":{"features":["feed","ops"],"hub":{"impl":"rust","version":"0.1.0","build":"abc1234"},"backup":null}}"#
        let h = try JSONDecoder().decode(HubHello.self, from: Data(rust.utf8))
        XCTAssertEqual(h.features, ["feed", "ops"])
        XCTAssertEqual(h.v2?.hub?.impl, "rust")
        let node = #"{"hub":"nexus-hub","protocol":1,"folderId":"f","seq":3,"devices":[]}"#
        XCTAssertNil(try JSONDecoder().decode(HubHello.self, from: Data(node.utf8)).v2)
        // a v2 this app can't read is no v2, and the hello still works
        let odd = #"{"hub":"nexus-hub","protocol":1,"folderId":"f","seq":3,"v2":"later"}"#
        XCTAssertEqual(try JSONDecoder().decode(HubHello.self, from: Data(odd.utf8)).features, [])
    }

    func testFeedLines() {
        XCTAssertEqual(HubFeedEvent.parse(#"{"type":"hello","hub":"nexus-hub","folderId":"f","seq":4}"#), .changes(folderId: "f", seq: 4))
        XCTAssertEqual(HubFeedEvent.parse(#"{"type":"changes","folderId":"f","seq":5,"changes":[{"path":"a.md","hash":"x","seq":5}]}"#), .changes(folderId: "f", seq: 5))
        XCTAssertEqual(HubFeedEvent.parse(#"{"type":"ping","seq":5}"#), .ping(seq: 5))
        XCTAssertEqual(HubFeedEvent.parse(#"{"type":"presence","presence":[],"psig":"p1"}"#), .presence(HubPresenceReply(presence: [], psig: "p1")))
        XCTAssertNil(HubFeedEvent.parse(#"{"type":"later"}"#))
        XCTAssertNil(HubFeedEvent.parse("not json"))
    }

    func testAWriteSentAgainAfterALostAnswerCarriesTheSameOp() async throws {
        let c = try await agreed()
        try put("notes/a.md", "A\nB\n")
        hub.loseNextAnswer = true
        do { _ = try await c.cycle(); XCTFail("the lost answer should look offline") } catch let e as SyncError { XCTAssertTrue(e.isTransient) }
        XCTAssertEqual(hub.text("notes/a.md"), "A\nB\n") // the hub did it
        _ = synced(try await c.cycle())
        XCTAssertEqual(hub.opsSeen.count, 2)
        let first = try XCTUnwrap(hub.opsSeen[0])
        XCTAssertEqual(hub.opsSeen[1], first, "the same write again: the same op id, so the hub answers it from the first time")
        XCTAssertEqual(read("notes/a.md"), "A\nB\n")

        // the next write of the same path is a new op
        try put("notes/a.md", "A\nB\nC\n")
        _ = synced(try await c.cycle())
        XCTAssertNotEqual(hub.opsSeen.last ?? nil, first)
        XCTAssertEqual(hub.text("notes/a.md"), "A\nB\nC\n")
    }

    func testADeletionCarriesAnOpToo() async throws {
        let c = try await agreed()
        try rm("b.yaml")
        hub.loseNextAnswer = true
        _ = try? await c.cycle()
        _ = synced(try await c.cycle())
        XCTAssertEqual(hub.opsSeen.count, 2)
        XCTAssertNotNil(hub.opsSeen[0])
        XCTAssertEqual(hub.opsSeen[0], hub.opsSeen[1])
        XCTAssertNil(hub.text("b.yaml"))
    }

    func testANodeHubGetsNoOps() async throws {
        hub.features = []
        let c = try await agreed()
        try put("notes/a.md", "A2\n")
        _ = synced(try await c.cycle())
        XCTAssertEqual(hub.opsSeen, [nil])
        let feeds = await c.followsFeed
        XCTAssertFalse(feeds)
    }

    func testTheFeedWakesTheWaitWhenTheHubChanges() async throws {
        let c = try await agreed()
        let follows = await c.followsFeed
        XCTAssertTrue(follows)
        let wait = Task { try await c.waitForHub(seconds: 30) }
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(hub.feedsOpened, 1)
        hub.write("notes/a.md", "from the laptop\n")
        let woke = try await wait.value
        XCTAssertTrue(woke)
        _ = synced(try await c.cycle())
        XCTAssertEqual(read("notes/a.md"), "from the laptop\n")
    }

    func testTheFeedSaysAtOnceWhenTheHubIsAlreadyAhead() async throws {
        let c = try await agreed()
        hub.write("b.yaml", "b: 2\n")
        let woke = try await c.waitForHub(seconds: 30)
        XCTAssertTrue(woke)
    }

    func testTheFeedTimesOutAndEndsWhenTheHubClosesIt() async throws {
        let c = try await agreed()
        let quiet = try await c.waitForHub(seconds: 1)
        XCTAssertFalse(quiet)
        let wait = Task { try await c.waitForHub(seconds: 30) }
        try await Task.sleep(nanoseconds: 200_000_000)
        hub.closeFeeds()
        let closed = try await wait.value
        XCTAssertFalse(closed)
    }

    func testWhatWaitsHereWhileOffline() async throws {
        let c = try await agreed()
        let none = await c.waitingHere()
        XCTAssertEqual(none, 0)
        try put("notes/a.md", "changed offline\n")
        try put("notes/new.md", "new\n")
        try rm("b.yaml")
        await c.changedEverywhere()
        hub.offline = true
        let n = await c.waitingHere()
        XCTAssertEqual(n, 3)
        hub.offline = false
        _ = synced(try await c.cycle())
        let after = await c.waitingHere()
        XCTAssertEqual(after, 0)
    }

    // MARK: the chip's words (the same as the laptop's, hubstate.js syncChipOf)

    func testTheChipsWords() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(SyncChip.of(.off).tone, .hidden)
        XCTAssertEqual(SyncChip.of(.notSetUp).tone, .hidden)
        XCTAssertEqual(SyncChip.of(.inSync, lastSynced: now.addingTimeInterval(-300), now: now),
                       SyncChip(tone: .ok, text: "In sync", detail: "Up to date with the hub; last synced 5 min ago."))
        XCTAssertEqual(SyncChip.of(.inSync).detail, "Up to date with the hub.")
        XCTAssertEqual(SyncChip.of(.syncing(3)).text, "Syncing 3")
        XCTAssertEqual(SyncChip.of(.syncing(1)).detail, "Sending 1 file to the hub.")
        XCTAssertEqual(SyncChip.of(.connecting).text, "Syncing…")
        XCTAssertEqual(SyncChip.of(.offline, waiting: 4).text, "Offline · 4 waiting")
        XCTAssertEqual(SyncChip.of(.offline, waiting: 4).detail, "The hub cannot be reached. 4 files changed here go up when it is back.")
        XCTAssertEqual(SyncChip.of(.offline).text, "Offline")
        XCTAssertEqual(SyncChip.of(.offline).tone, .warn)
        XCTAssertEqual(SyncChip.of(.problem("The hub didn't accept the token.")), SyncChip(tone: .bad, text: "Sync problem", detail: "The hub didn't accept the token."))
        XCTAssertEqual(SyncChip.of(.deletionsHeld(30)).text, "Deletions held")
        XCTAssertEqual(SyncChip.of(.waiting("This folder has no nexus.yaml.")).text, "Not syncing")
        XCTAssertEqual(SyncChip.of(.inSync, conflicts: 1).text, "1 conflict")
        XCTAssertEqual(SyncChip.of(.syncing(2), conflicts: 2).text, "2 conflicts")
        XCTAssertEqual(SyncChip.of(.offline, waiting: 2, conflicts: 2).text, "Offline · 2 waiting") // offline says more than conflicts
        XCTAssertEqual(SyncChip.ago(now.addingTimeInterval(-30), now), "just now")
        XCTAssertEqual(SyncChip.ago(now.addingTimeInterval(-7200), now), "2 h ago")
        XCTAssertEqual(SyncChip.ago(now.addingTimeInterval(-3 * 86400), now), "3 days ago")
    }
}
