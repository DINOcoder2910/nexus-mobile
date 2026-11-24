import XCTest
@testable import NexusCore

/// The handwriting the iPad shares with the laptop in a board's folder (HandwritingShare.swift; read by nexus
/// desktop/backend/src/find.rs, whose test reads the same shape).
final class HandwritingShareTests: XCTestCase {
    func testWrittenOnlyWhenTheWordsChangeAndRemovedWhenNoneAreLeft() throws {
        let board = FileManager.default.temporaryDirectory.appendingPathComponent("hw-\(UUID().uuidString).board", isDirectory: true)
        try FileManager.default.createDirectory(at: board, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: board) }
        let url = board.appendingPathComponent(HandwritingShare.file)
        let lines = [HandwritingShare.Line(text: "Oxidation is loss", x: 120.04, y: 80.26, w: 300, h: 40),
                     HandwritingShare.Line(text: "\"OIL RIG\"", x: 120, y: 130, w: 180.55, h: 38)]
        XCTAssertTrue(try HandwritingShare.write(lines, board: board, device: "iPad", now: Date(timeIntervalSince1970: 1_795_400_000)))
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("{\"format\":\"nexus-handwriting/1\",\"device\":\"iPad\",\"read\":\"2026-11-23T"), text)
        XCTAssertTrue(text.contains("{\"text\":\"Oxidation is loss\",\"x\":120,\"y\":80.3,\"w\":300,\"h\":40}"), text)
        XCTAssertEqual(HandwritingShare.lines(in: text), lines)
        // the same words read again: the file stays as it is (nothing for sync to carry)
        XCTAssertFalse(try HandwritingShare.write(lines, board: board, device: "iPad", now: Date()))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), text)
        // a word changed
        XCTAssertTrue(try HandwritingShare.write([lines[0]], board: board, device: "iPad"))
        XCTAssertEqual(HandwritingShare.lines(in: try String(contentsOf: url, encoding: .utf8))?.count, 1)
        // the ink erased: the file goes
        XCTAssertTrue(try HandwritingShare.write([], board: board, device: "iPad"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(try HandwritingShare.write([], board: board, device: "iPad"))
        XCTAssertNil(HandwritingShare.lines(in: "{\"format\":\"something-else\",\"lines\":[]}"))
    }
}
