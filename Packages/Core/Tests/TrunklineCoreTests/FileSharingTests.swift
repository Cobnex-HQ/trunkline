import XCTest
@testable import TrunklineCore

final class FileSharingTests: XCTestCase {
    func testUnicodeInputChunksPreserveLongGraphemesAndSurrogates() {
        let original = "echo café 👩🏽‍💻 " + String(repeating: "👨‍👩‍👧‍👦", count: 10)
        let chunks = UnicodeInput.chunks(original)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 20 })
        XCTAssertEqual(String(decoding: chunks.flatMap { $0 }, as: UTF16.self), original)
        for chunk in chunks {
            XCTAssertFalse((0xd800...0xdbff).contains(chunk.last ?? 0))
            XCTAssertFalse((0xdc00...0xdfff).contains(chunk.first ?? 0))
        }
    }
    func testShareDirectoryRejectsTraversalAndSymlinkEscape() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = directory.appendingPathComponent("share")
        let outside = directory.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)
        XCTAssertEqual(try ShareDirectory.resolve("file.txt", root: root), root.appendingPathComponent("file.txt"))
        XCTAssertThrowsError(try ShareDirectory.resolve("../outside/file.txt", root: root))
        XCTAssertThrowsError(try ShareDirectory.resolve("escape/file.txt", root: root))
        XCTAssertThrowsError(try ShareDirectory.resolve("/etc/passwd", root: root))
    }
}

final class TransferTests: XCTestCase {
    func testTransferRequiresSequentialChunksAndNeverOverwrites() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("result.txt")
        let incoming = try IncomingTransfer(destination: destination, expectedSize: 5)
        XCTAssertThrowsError(try incoming.append(Data("hi".utf8), offset: 1))
        try incoming.append(Data("hello".utf8), offset: 0)
        XCTAssertThrowsError(try incoming.append(Data([1]), offset: 5))
        try incoming.finish()
        XCTAssertEqual(try String(contentsOf: destination), "hello")
        let another = try IncomingTransfer(destination: destination, expectedSize: 1)
        try another.append(Data([1]), offset: 0)
        XCTAssertThrowsError(try another.finish())
        XCTAssertEqual(try String(contentsOf: destination), "hello")
    }
    func testIncompleteTransferCannotBeFinalized() throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let incoming = try IncomingTransfer(destination: destination, expectedSize: 10)
        XCTAssertThrowsError(try incoming.finish())
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertThrowsError(try IncomingTransfer(destination: destination, expectedSize: -1))
    }
}

final class PowerTests: XCTestCase {
    func testClosedLidRestoresOriginalSleepPolicy() {
        let enter = PowerTransition(mode: .lidClosed, systemDisabled: false, originalDisabled: nil)
        XCTAssertEqual(enter.changeDisabled, true)
        XCTAssertEqual(enter.savedOriginal, false)
        let exit = PowerTransition(mode: .off, systemDisabled: true, originalDisabled: enter.savedOriginal)
        XCTAssertEqual(exit.changeDisabled, false)
        XCTAssertNil(exit.savedOriginal)
    }
    func testDoesNotEnableSleepWhenAnotherAppHadDisabledIt() {
        let enter = PowerTransition(mode: .lidClosed, systemDisabled: true, originalDisabled: nil)
        XCTAssertNil(enter.changeDisabled)
        XCTAssertEqual(enter.savedOriginal, true)
        let exit = PowerTransition(mode: .system, systemDisabled: true, originalDisabled: enter.savedOriginal)
        XCTAssertNil(exit.changeDisabled)
        XCTAssertNil(exit.savedOriginal)
    }
}
