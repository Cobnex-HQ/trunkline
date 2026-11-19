import XCTest
@testable import TrunklineCore

final class ResumableFileTests: XCTestCase {
    func testLostUploadAcknowledgmentResumesAtCommittedOffsetAndCompletesOnce() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = ResumableFileService()
        let ticket = FileTransferTicket()
        let offer = FileTransferOffer(ticket: ticket, path: "sample.txt", direction: .upload, size: 6)
        XCTAssertEqual(service.handle(.open(offer), root: root).offset, 0)
        XCTAssertEqual(service.handle(.write(ticket, offset: 0, bytes: Data("abc".utf8)), root: root).offset, 3)
        // The client loses the acknowledgment and repeats its original offer.
        XCTAssertEqual(service.handle(.open(offer), root: root).offset, 3)
        let done = service.handle(.write(ticket, offset: 3, bytes: Data("def".utf8)), root: root)
        XCTAssertTrue(done.complete)
        XCTAssertTrue(service.handle(.open(offer), root: root).complete)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("sample.txt")), Data("abcdef".utf8))
    }
    func testWrongTicketCannotReadCancelOrResumeAnotherTransfer() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = ResumableFileService(), ticket = FileTransferTicket()
        let offer = FileTransferOffer(ticket: ticket, path: "private.txt", direction: .upload, size: 6)
        _ = service.handle(.open(offer), root: root)
        _ = service.handle(.write(ticket, offset: 0, bytes: Data("abc".utf8)), root: root)
        let wrong = FileTransferTicket(id: ticket.id, secret: UUID())
        XCTAssertNotNil(service.handle(.cancel(wrong), root: root).error)
        XCTAssertNotNil(service.handle(.read(wrong, offset: 0), root: root).error)
        XCTAssertEqual(service.handle(.open(offer), root: root).offset, 3)
        XCTAssertTrue(service.handle(.cancel(ticket), root: root).cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("private.txt").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }
    func testCancellationIsIdempotentAndReportsAlreadyCommittedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = ResumableFileService(), ticket = FileTransferTicket()
        XCTAssertTrue(service.handle(.cancel(ticket), root: root).cancelled)
        let offer = FileTransferOffer(ticket: ticket, path: "empty", direction: .upload, size: 0)
        _ = service.handle(.open(offer), root: root)
        _ = service.handle(.write(ticket, offset: 0, bytes: Data()), root: root)
        let reply = service.handle(.cancel(ticket), root: root)
        XCTAssertTrue(reply.complete)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("empty").path))
    }
    func testDownloadResumeRejectsChangedSourceAndDifferentSharedFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("source.txt")
        try Data("original".utf8).write(to: file)
        let service = ResumableFileService(), ticket = FileTransferTicket()
        let offer = FileTransferOffer(ticket: ticket, path: "source.txt", direction: .download, size: 0)
        XCTAssertNil(service.handle(.open(offer), root: root).error)
        XCTAssertEqual(service.handle(.read(ticket, offset: 3), root: root).bytes, Data("ginal".utf8))
        XCTAssertNotNil(service.handle(.open(offer), root: root.appendingPathComponent("other")).error)
        try Data("replaced".utf8).write(to: file, options: .atomic)
        XCTAssertNotNil(service.handle(.read(ticket, offset: 0), root: root).error)
    }
}
