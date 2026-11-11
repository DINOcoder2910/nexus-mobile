import XCTest
@testable import NexusCore

/// The sync client against an in-process hub (FakeHub), on a data folder in a temp directory.
final class SyncTests: XCTestCase {
    var root: URL!
    var dir: URL!
    var stateURL: URL!
    var hub: FakeHub!
    let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("nexus-sync-\(UUID().uuidString)")
        dir = root.appendingPathComponent("nexus-data")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        stateURL = root.appendingPathComponent("state/sync.json")
        hub = FakeHub()
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    // MARK: helpers

    func client() -> SyncClient {
        SyncClient(folder: dir, stateURL: stateURL, hubUrl: "http://hub.test:8743", transport: hub)
    }

    func put(_ rel: String, _ text: String) throws {
        let u = dir.appendingPathComponent(rel)
        try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: u)
    }

    func read(_ rel: String) -> String? {
        (try? Data(contentsOf: dir.appendingPathComponent(rel))).map { String(decoding: $0, as: UTF8.self) }
    }

    func exists(_ rel: String) -> Bool { fm.fileExists(atPath: dir.appendingPathComponent(rel).path) }

    func rm(_ rel: String) throws { try fm.removeItem(at: dir.appendingPathComponent(rel)) }

    func hash(_ text: String) -> String { SyncHash.data(Data(text.utf8)) }

    func synced(_ o: SyncOutcome, file: StaticString = #filePath, line: UInt = #line) -> SyncReport {
        guard case .synced(let r) = o else {
            XCTFail("expected a sync, got \(o)", file: file, line: line)
            return SyncReport()
        }
        return r
    }

    /// A hub and this iPad that agree on nexus.yaml and a few files.
    func agreed() async throws -> SyncClient {
        hub.write("nexus.yaml", "nexus: 2\n")
        hub.write("notes/a.md", "A\n")
        hub.write("b.yaml", "b: 1\n")
        hub.write("old/deep/c.md", "C\n")
        let c = client()
        _ = synced(try await c.cycle())
        XCTAssertEqual(read("notes/a.md"), "A\n")
        hub.resetCounts()
        return c
    }

    // MARK: paths

    func testPathRules() {
        XCTAssertTrue(SyncPaths.isSafe("classes/beta/tasks.yaml"))
        XCTAssertTrue(SyncPaths.isSafe("notes/caf\u{e9}.md"))
        XCTAssertFalse(SyncPaths.isSafe("notes/cafe\u{301}.md")) // NFD
        for bad in ["", "/abs.md", "a//b.md", "./a.md", "a/../b.md", "a\\b.md", "a:b.md", "what?.md", "q\".md", "x<y.md",
                    "pipe|.md", "star*.md", "dot./a.md", "space /a.md", "end.", "tab\t.md", "nul\u{0}.md", "del\u{7f}.md",
                    String(repeating: "a", count: 401)] {
            XCTAssertFalse(SyncPaths.isSafe(bad), bad)
        }
        XCTAssertTrue(SyncPaths.isSafe(String(repeating: "a", count: 400)))

        for ignored in [".git/config", "a/.git/HEAD", ".nexus/x.json", "node_modules/a/b.js", "x/.Trash/y.md", ".stversions/a",
                        ".DS_Store", "a/Thumbs.db", "THUMBS.DB", "desktop.ini", "a/b.tmp", "x.TMP", "c.renaming", "~$Report.docx",
                        "a/b.partial", ".~lock.notes.odt#", ".syncthing.a.md.tmp", ".Spotlight-V100/x", ".sync/state"] {
            XCTAssertTrue(SyncPaths.isIgnored(ignored), ignored)
        }
        for kept in ["notes/a.md", ".gitignore", "a/.nexusrc", "tmp/a.md", "partial.md", "files/report.pdf"] {
            XCTAssertFalse(SyncPaths.isIgnored(kept), kept)
        }
        XCTAssertTrue(SyncPaths.isConflictCopy("classes/tasks (conflict iPad 2026-11-12 0815).yaml"))
        XCTAssertTrue(SyncPaths.isConflictCopy("notes (conflict Zephyrus Duo 16 2026-11-12 0815 2).md"))
        XCTAssertFalse(SyncPaths.isConflictCopy("notes/conflict notes.md"))
    }

    func testHubAddress() {
        XCTAssertEqual(HTTPSyncTransport.hubURL("100.64.0.1")?.absoluteString, "http://100.64.0.1:8743")
        XCTAssertEqual(HTTPSyncTransport.hubURL(" g14 ")?.absoluteString, "http://g14:8743")
        XCTAssertEqual(HTTPSyncTransport.hubURL("g14:9000")?.absoluteString, "http://g14:9000")
        XCTAssertEqual(HTTPSyncTransport.hubURL("http://g14.tail1234.ts.net:8743/")?.absoluteString, "http://g14.tail1234.ts.net:8743")
        XCTAssertEqual(HTTPSyncTransport.hubURL("http://g14")?.absoluteString, "http://g14:8743")
        XCTAssertEqual(HTTPSyncTransport.hubURL("https://hub.example.net")?.absoluteString, "https://hub.example.net")
        XCTAssertNil(HTTPSyncTransport.hubURL(""))
        XCTAssertNil(HTTPSyncTransport.hubURL("ftp://g14"))
    }

    func testRequestsCarryTheTokenAndAnEncodedPath() throws {
        let t = HTTPSyncTransport(base: try XCTUnwrap(URL(string: "http://g14:8743")), token: "tok", device: "iPad")
        let r = try t.request("file", [("path", "a b/c&d+caf\u{e9}.md"), ("base", "none")], method: "PUT")
        XCTAssertEqual(r.url?.absoluteString, "http://g14:8743/v1/file?path=a%20b%2Fc%26d%2Bcaf%C3%A9.md&base=none")
        XCTAssertEqual(r.httpMethod, "PUT")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Nexus-Device"), "iPad")
    }

    func testStateKeepsTheSpecsShape() throws {
        let one = try JSONEncoder().encode(CachedHash(size: 3, mtimeMs: 1731312345123, hash: "ab"))
        let json = String(decoding: one, as: UTF8.self)
        XCTAssertTrue(json.hasPrefix("[3,1731312345123"), json)
        XCTAssertTrue(json.hasSuffix(",\"ab\"]"), json)
        XCTAssertEqual(try JSONDecoder().decode(CachedHash.self, from: Data("[3,1731312345123.5,\"ab\"]".utf8)).mtimeMs, 1731312345123.5)
        var s = SyncState(hubUrl: "http://g14:8743")
        s.folderId = "f"
        s.cursor = 7
        s.bases = ["a.md": "h"]
        s.hashCache = ["a.md": CachedHash(size: 1, mtimeMs: 2.5, hash: "h")]
        try s.save(to: stateURL)
        XCTAssertEqual(SyncState.load(stateURL), s)
        XCTAssertEqual(SyncState.fileName(forKey: "x"), SyncState.fileName(forKey: "x"))
        XCTAssertNotEqual(SyncState.fileName(forKey: "x"), SyncState.fileName(forKey: "y"))
    }

    // MARK: first sync

    func testFirstSyncIntoAnEmptyFolderDownloadsEverything() async throws {
        hub.write("nexus.yaml", "nexus: 2\n")
        hub.write("classes/beta/tasks.yaml", "tasks: []\n")
        hub.write("files/big.pdf", String(repeating: "%PDF", count: 10_000))
        hub.write("gone.md", "x\n")
        hub.remove("gone.md")
        let c = client()
        let r = synced(try await c.cycle())
        XCTAssertEqual(read("classes/beta/tasks.yaml"), "tasks: []\n")
        XCTAssertEqual(read("files/big.pdf")?.count, 40_000)
        XCTAssertFalse(exists("gone.md"))
        XCTAssertEqual(Set(r.pulled), ["nexus.yaml", "classes/beta/tasks.yaml", "files/big.pdf"])
        XCTAssertEqual(hub.puts, [])
        let s = await c.state
        XCTAssertEqual(s.folderId, "hub-1")
        XCTAssertEqual(s.cursor, hub.seq)
        XCTAssertNil(s.restoring)
        XCTAssertEqual(s.bases["nexus.yaml"], hash("nexus: 2\n"))
        XCTAssertNil(s.bases["gone.md"])
        // No temp files left behind, and the state is saved outside the folder.
        let names = try fm.subpathsOfDirectory(atPath: dir.path)
        XCTAssertFalse(names.contains { $0.hasSuffix(".partial") })
        XCTAssertEqual(SyncState.load(stateURL)?.cursor, hub.seq)
        // A second cycle has nothing to do.
        hub.resetCounts()
        let again = synced(try await c.cycle())
        XCTAssertEqual(again.pushed, [])
        XCTAssertEqual(again.pulled, [])
        XCTAssertEqual(hub.downloads, [])
    }

    func testTheIPadNeverSeedsAnEmptyHub() async throws {
        try put("nexus.yaml", "nexus: 2\n")
        try put("notes/a.md", "A\n")
        let r = try await client().cycle()
        XCTAssertEqual(r, .hubEmpty)
        XCTAssertEqual(hub.puts, [])
    }

    func testFirstSyncAsksWhenBothSidesHaveDifferentFiles() async throws {
        hub.write("nexus.yaml", "nexus: 2\n")
        hub.write("b.yaml", "b: from the hub\n")
        hub.write("hub-only.md", "H\n")
        try put("nexus.yaml", "nexus: 2\n")
        try put("b.yaml", "b: from this iPad\n")
        try put("ipad-only.md", "I\n")
        let c = client()
        guard case .needsFirstSyncChoice(let s) = try await c.cycle() else { return XCTFail("expected the question") }
        XCTAssertEqual(s.hubFiles, 3)
        XCTAssertEqual(s.localFiles, 3)
        XCTAssertEqual(s.same, 1)
        XCTAssertEqual(s.differ, 1)
        XCTAssertEqual(s.onlyHere, 1)
        XCTAssertEqual(s.onlyOnHub, 1)
        XCTAssertTrue(s.localIsDataFolder)
        XCTAssertEqual(hub.puts, [])
        XCTAssertEqual(read("b.yaml"), "b: from this iPad\n")
        // Asking again changes nothing.
        guard case .needsFirstSyncChoice = try await c.cycle() else { return XCTFail("expected the question again") }

        // "Merge with this iPad's files": only differences are sent; a different file becomes a conflict copy.
        try await c.mergeWithHub()
        let r = synced(try await c.cycle())
        XCTAssertEqual(Set(hub.puts), ["b.yaml", "ipad-only.md"])
        XCTAssertEqual(read("b.yaml"), "b: from the hub\n")
        XCTAssertEqual(hub.text("ipad-only.md"), "I\n")
        XCTAssertEqual(read("hub-only.md"), "H\n")
        let copy = "b (conflict iPad 2026-11-12 0815).yaml"
        XCTAssertEqual(read(copy), "b: from this iPad\n")
        XCTAssertEqual(r.conflictCopies, [copy])
    }

    func testFirstSyncWithTheSameFilesDoesNotAsk() async throws {
        hub.write("nexus.yaml", "nexus: 2\n")
        hub.write("files/report.pdf", "PDF bytes")
        hub.write("hub-only.md", "H\n")
        try put("nexus.yaml", "nexus: 2\n")
        try put("files/report.pdf", "PDF bytes")
        let r = synced(try await client().cycle())
        XCTAssertEqual(hub.puts, [])
        XCTAssertEqual(r.pulled, ["hub-only.md"])
    }

    func testUseTheHubsCopyMovesTheFolderAside() async throws {
        hub.write("nexus.yaml", "nexus: 2\n")
        hub.write("b.yaml", "b: from the hub\n")
        try put("nexus.yaml", "nexus: 2\n")
        try put("b.yaml", "b: from this iPad\n")
        try put("ipad-only.md", "I\n")
        let c = client()
        guard case .needsFirstSyncChoice = try await c.cycle() else { return XCTFail("expected the question") }
        let moved = try await c.useHubCopy(now: Date(timeIntervalSince1970: 1_762_870_000))
        let aside = try XCTUnwrap(moved)
        XCTAssertEqual(aside.deletingLastPathComponent().standardizedFileURL.path, root.standardizedFileURL.path)
        XCTAssertTrue(aside.lastPathComponent.hasPrefix("nexus-data before sync 20"), aside.lastPathComponent)
        XCTAssertEqual(try String(contentsOf: aside.appendingPathComponent("ipad-only.md"), encoding: .utf8), "I\n")
        let r = synced(try await c.cycle())
        XCTAssertEqual(hub.puts, [])
        XCTAssertEqual(read("b.yaml"), "b: from the hub\n")
        XCTAssertFalse(exists("ipad-only.md"))
        XCTAssertEqual(Set(r.pulled), ["nexus.yaml", "b.yaml"])
        let s = await c.state
        XCTAssertNil(s.restoring)
        // Then it syncs normally.
        try put("new.md", "new here\n")
        _ = synced(try await c.cycle())
        XCTAssertEqual(hub.text("new.md"), "new here\n")
    }

    // MARK: push and pull

    func testPushNewChangedAndDeleted() async throws {
        let c = try await agreed()
        try put("notes/new.md", "new\n")
        try put("b.yaml", "b: 2 changed here\n")
        try rm("notes/a.md")
        let r = synced(try await c.cycle())
        XCTAssertEqual(Set(r.pushed), ["notes/new.md", "b.yaml", "notes/a.md"])
        XCTAssertEqual(hub.text("notes/new.md"), "new\n")
        XCTAssertEqual(hub.text("b.yaml"), "b: 2 changed here\n")
        XCTAssertNil(hub.files["notes/a.md"])
        XCTAssertEqual(hub.deletes, ["notes/a.md"])
        let s = await c.state
        XCTAssertEqual(s.bases["b.yaml"], hash("b: 2 changed here\n"))
        XCTAssertNil(s.bases["notes/a.md"])
        XCTAssertEqual(r.pulled, [])
        XCTAssertEqual(hub.downloads, [])
    }

    func testPullOtherDevicesChanges() async throws {
        let c = try await agreed()
        hub.write("notes/a.md", "A, edited on the laptop\n")
        hub.write("x/y/new.md", "made on the laptop\n")
        hub.remove("old/deep/c.md")
        let r = synced(try await c.cycle())
        XCTAssertEqual(read("notes/a.md"), "A, edited on the laptop\n")
        XCTAssertEqual(read("x/y/new.md"), "made on the laptop\n")
        XCTAssertFalse(exists("old/deep/c.md"))
        XCTAssertFalse(exists("old"), "a folder left empty by a deletion is removed")
        XCTAssertEqual(Set(r.pulled), ["notes/a.md", "x/y/new.md", "old/deep/c.md"])
        XCTAssertEqual(hub.puts, [])
        let s = await c.state
        XCTAssertEqual(s.cursor, hub.seq)
        XCTAssertEqual(s.bases["x/y/new.md"], hash("made on the laptop\n"))
        XCTAssertNil(s.bases["old/deep/c.md"])
    }

    func testAFileChangedHereDuringADownloadIsNotOverwritten() async throws {
        let c = try await agreed()
        hub.write("notes/a.md", "A, edited on the laptop\n")
        hub.onDownload = { [unowned self] p in
            if p == "notes/a.md" { try? self.put("notes/a.md", "A, edited on the iPad meanwhile\n") }
        }
        _ = synced(try await c.cycle())
        XCTAssertEqual(read("notes/a.md"), "A, edited on the iPad meanwhile\n")
        let s = await c.state
        XCTAssertEqual(s.bases["notes/a.md"], hash("A\n"), "the base stays the last agreed version")

        // The next cycle sends the iPad's edit on the old base: the hub can't merge it, so both are kept.
        hub.onDownload = nil
        _ = synced(try await c.cycle())
        XCTAssertEqual(hub.text("notes/a.md"), "A, edited on the laptop\n")
        XCTAssertEqual(read("notes/a.md"), "A, edited on the laptop\n")
        XCTAssertEqual(read("notes/a (conflict iPad 2026-11-12 0815).md"), "A, edited on the iPad meanwhile\n")
    }

    func testAConflictDownloadsTheHubsVersionAndTheCopy() async throws {
        let c = try await agreed()
        hub.write("b.yaml", "b: laptop\n")
        try put("b.yaml", "b: ipad version\n")
        let r = synced(try await c.cycle())
        XCTAssertEqual(read("b.yaml"), "b: laptop\n")
        let copy = "b (conflict iPad 2026-11-12 0815).yaml"
        XCTAssertEqual(read(copy), "b: ipad version\n")
        XCTAssertEqual(hub.text(copy), "b: ipad version\n")
        XCTAssertEqual(r.conflictCopies, [copy])
        let s = await c.state
        XCTAssertEqual(s.bases["b.yaml"], hash("b: laptop\n"))
        XCTAssertEqual(s.bases[copy], hash("b: ipad version\n"))
        hub.resetCounts()
        _ = synced(try await c.cycle())
        XCTAssertEqual(hub.puts, [], "nothing is sent again")
    }

    func testAMergeIsDownloaded() async throws {
        let c = try await agreed()
        hub.mergeHook = { _, theirs, mine in theirs + mine }
        hub.write("b.yaml", "b: 1\nlaptop: yes\n")
        try put("b.yaml", "b: 1\nipad: yes, longer\n")
        let r = synced(try await c.cycle())
        XCTAssertEqual(read("b.yaml"), "b: 1\nlaptop: yes\nb: 1\nipad: yes, longer\n")
        XCTAssertEqual(r.conflictCopies, [])
        let s = await c.state
        XCTAssertEqual(s.bases["b.yaml"], hash("b: 1\nlaptop: yes\nb: 1\nipad: yes, longer\n"))
    }

    func testADeletionAgainstAnEditKeepsTheEdit() async throws {
        let c = try await agreed()
        hub.write("notes/a.md", "A, edited on the laptop\n")
        try rm("notes/a.md")
        let r = synced(try await c.cycle())
        XCTAssertEqual(hub.deletes, ["notes/a.md"])
        XCTAssertEqual(hub.text("notes/a.md"), "A, edited on the laptop\n")
        XCTAssertEqual(read("notes/a.md"), "A, edited on the laptop\n")
        XCTAssertTrue(r.pulled.contains("notes/a.md"))
        let s = await c.state
        XCTAssertEqual(s.bases["notes/a.md"], hash("A, edited on the laptop\n"))
    }

    func testAnEditHereAgainstADeletionThereIsSentAgain() async throws {
        let c = try await agreed()
        hub.remove("notes/a.md")
        try put("notes/a.md", "A, still wanted here\n")
        _ = synced(try await c.cycle())
        XCTAssertEqual(read("notes/a.md"), "A, still wanted here\n")
        XCTAssertEqual(hub.text("notes/a.md"), "A, still wanted here\n")
    }

    // MARK: what is left alone

    func testIgnoredFilesStayHere() async throws {
        let c = try await agreed()
        for p in [".DS_Store", "notes/x.tmp", ".git/config", "~$Essay.docx", "node_modules/a.js", "a.partial", ".nexus/cache.json"] {
            try put(p, "local only\n")
        }
        hub.injected = [HubChange(path: ".git/HEAD", hash: hash("x"), seq: 99)]
        let r = synced(try await c.cycle())
        XCTAssertEqual(hub.puts, [])
        XCTAssertEqual(r.pushed, [])
        XCTAssertFalse(exists(".git/HEAD"))
        XCTAssertEqual(hub.downloads, [])
    }

    func testUnsafePathsAreLeftAlone() async throws {
        let c = try await agreed()
        try put("bad:name.md", "colon\n")
        try put("ends with a dot.", "dot\n")
        try put("cafe\u{301}.md", "decomposed name\n")
        hub.injected = [HubChange(path: "../evil.md", hash: hash("evil"), seq: 98),
                        HubChange(path: "a\\b.md", hash: hash("evil"), seq: 99)]
        let r = synced(try await c.cycle())
        XCTAssertFalse(hub.puts.contains("bad:name.md"))
        XCTAssertFalse(hub.puts.contains("ends with a dot."))
        XCTAssertTrue(r.problems.contains { $0.path == "bad:name.md" })
        XCTAssertTrue(r.problems.contains { $0.path == "ends with a dot." })
        XCTAssertTrue(r.problems.contains { $0.path == "../evil.md" })
        XCTAssertEqual(read("bad:name.md"), "colon\n")
        // A decomposed name is sent in its NFC form.
        XCTAssertTrue(hub.puts.contains { $0.unicodeScalars.elementsEqual("caf\u{e9}.md".unicodeScalars) })
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("evil.md").path))
        XCTAssertFalse(hub.downloads.contains("../evil.md"))
        hub.resetCounts()
        _ = synced(try await c.cycle())
        XCTAssertEqual(hub.puts, [], "an unsafe file is never sent, and an NFC one is sent once")
    }

    func testAClashOfCapitalsIsReportedAndLeftAlone() async throws {
        let c = try await agreed()
        hub.write("Plan.md", "the laptop's plan\n")
        try put("plan.md", "the iPad's own plan, longer\n")
        let r = synced(try await c.cycle())
        XCTAssertTrue(r.problems.contains { $0.path == "plan.md" })
        XCTAssertEqual(read("plan.md"), "the iPad's own plan, longer\n")
        XCTAssertEqual(hub.text("Plan.md"), "the laptop's plan\n")
        XCTAssertEqual(hub.puts, ["plan.md"])
        hub.resetCounts()
        let again = synced(try await c.cycle())
        XCTAssertEqual(hub.puts, [], "not sent again until it changes")
        XCTAssertTrue(again.problems.contains { $0.path == "plan.md" })
    }

    // MARK: guards

    func testManyDeletionsPauseUntilTheUserSays() async throws {
        hub.write("nexus.yaml", "nexus: 2\n")
        for i in 0..<40 { hub.write("notes/n\(i).md", "note \(i)\n") }
        let c = client()
        _ = synced(try await c.cycle())
        hub.resetCounts()
        for i in 0..<30 { try rm("notes/n\(i).md") }
        guard case .pausedForDeletions(let paths) = try await c.cycle() else { return XCTFail("expected a pause") }
        XCTAssertEqual(paths.count, 30)
        XCTAssertEqual(hub.deletes, [])
        XCTAssertEqual(hub.files.count, 41)
        // Still paused on the next cycle.
        guard case .pausedForDeletions = try await c.cycle() else { return XCTFail("expected a pause again") }

        // "Bring them back from the hub".
        let back = try await c.bringBackDeleted()
        XCTAssertEqual(back.count, 30)
        XCTAssertEqual(read("notes/n0.md"), "note 0\n")
        _ = synced(try await c.cycle())
        XCTAssertEqual(hub.deletes, [])

        // Delete them again, and this time say yes.
        for i in 0..<30 { try rm("notes/n\(i).md") }
        guard case .pausedForDeletions = try await c.cycle() else { return XCTFail("expected a pause") }
        await c.allowPendingDeletions()
        _ = synced(try await c.cycle())
        XCTAssertEqual(hub.deletes.count, 30)
        XCTAssertEqual(hub.files.count, 11)
    }

    func testAFewDeletionsDoNotPause() async throws {
        hub.write("nexus.yaml", "nexus: 2\n")
        for i in 0..<200 { hub.write("notes/n\(i).md", "note \(i)\n") }
        let c = client()
        _ = synced(try await c.cycle())
        for i in 0..<30 { try rm("notes/n\(i).md") } // 30 > 25, but not a quarter of 201
        _ = synced(try await c.cycle())
        XCTAssertEqual(hub.deletes.count, 30)
    }

    func testAFolderWithoutNexusYamlDoesNothing() async throws {
        let c = try await agreed()
        // Everything gone (an unmounted or emptied folder): nothing is deleted on the hub, nothing downloaded.
        for p in try fm.contentsOfDirectory(atPath: dir.path) { try rm(p) }
        hub.write("notes/a.md", "A, edited on the laptop\n")
        let r = try await c.cycle()
        XCTAssertEqual(r, .notADataFolder)
        XCTAssertEqual(hub.deletes, [])
        XCTAssertEqual(hub.puts, [])
        XCTAssertEqual(hub.downloads, [])
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: dir.path).isEmpty)

        // Only nexus.yaml missing: the same.
        try put("b.yaml", "b: 1\n")
        let second = try await c.cycle()
        XCTAssertEqual(second, .notADataFolder)
        XCTAssertEqual(hub.deletes, [])

        // The folder itself missing: nothing, and it is not made again.
        try fm.removeItem(at: dir)
        let third = try await c.cycle()
        XCTAssertEqual(third, .notADataFolder)
        XCTAssertFalse(fm.fileExists(atPath: dir.path))
    }

    func testANewHubFolderResetsTheBases() async throws {
        let c = try await agreed()
        // The hub was made again from the same files: bases start over, and matching files are not sent.
        hub.folderId = "hub-2"
        _ = synced(try await c.cycle())
        var s = await c.state
        XCTAssertEqual(s.folderId, "hub-2")
        XCTAssertEqual(hub.puts, [])
        XCTAssertEqual(s.bases["b.yaml"], hash("b: 1\n"))
        XCTAssertEqual(s.cursor, hub.seq)

        // Made again with different files: ask how to start.
        hub.folderId = "hub-3"
        hub.write("b.yaml", "b: the rebuilt hub\n")
        guard case .needsFirstSyncChoice(let summary) = try await c.cycle() else { return XCTFail("expected the question") }
        XCTAssertEqual(summary.differ, 1)
        s = await c.state
        XCTAssertNil(s.folderId)
        XCTAssertEqual(s.bases, [:])
        XCTAssertEqual(hub.puts, [])
        XCTAssertEqual(read("b.yaml"), "b: 1\n")
    }

    func testOfflineIsTransientAndChangesNothing() async throws {
        let c = try await agreed()
        try put("notes/new.md", "new\n")
        hub.offline = true
        do {
            _ = try await c.cycle()
            XCTFail("expected offline")
        } catch let e as SyncError {
            XCTAssertTrue(e.isTransient)
        }
        hub.offline = false
        _ = synced(try await c.cycle())
        XCTAssertEqual(hub.text("notes/new.md"), "new\n")
    }

    func testTheStateSurvivesANewClient() async throws {
        _ = try await agreed()
        hub.resetCounts()
        let fresh = client()
        let r = synced(try await fresh.cycle())
        XCTAssertEqual(hub.puts, [])
        XCTAssertEqual(hub.downloads, [])
        XCTAssertEqual(r.pulled, [])
    }
}
