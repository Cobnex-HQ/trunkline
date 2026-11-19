import XCTest
@testable import TrunklineCore

@MainActor final class ResumableClientTests: XCTestCase {
    func testRetryAfterLostFinalReplyDoesNotDuplicateOrOverwriteUpload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let contents = Data(repeating: 83, count: 300_000)
        try contents.write(to: source)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: source) }
        let service = ResumableFileService()
        let client = ResumableFileClient(timeout: .milliseconds(80))
        client.connect(macID: "first")
        var drop = true
        client.send = { id, request in
            let reply = service.handle(request, root: root)
            if reply.complete && drop { drop = false; return }
            client.receive(id: id, reply: reply)
        }
        client.upload(source, parent: "")
        for _ in 0..<100 where client.state != .paused { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(client.state, .paused)
        client.disconnect()
        client.connect(macID: "first")
        client.retry()
        for _ in 0..<100 where client.state != .completed { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(client.state, .completed)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(source.lastPathComponent)), contents)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 1)
        client.send = nil
    }
    func testDownloadReconnectKeepsWrittenChunksAndIgnoresLateReplies() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = Data((0..<300_000).map { UInt8($0 % 251) })
        try contents.write(to: root.appendingPathComponent("download.bin"))
        let service = ResumableFileService(), client = ResumableFileClient(timeout: .milliseconds(60))
        client.connect(macID: "first")
        var offsets: [Int64] = [], delayed: (UUID, FileTransferReply)?
        client.send = { id, request in
            let reply = service.handle(request, root: root)
            if case let .read(_, offset) = request {
                offsets.append(offset)
                if offsets.count == 2 { delayed = (id, reply); return }
            }
            client.receive(id: id, reply: reply)
        }
        client.download(path: "download.bin", name: "download.bin")
        for _ in 0..<100 where client.state != .paused { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(client.received, 131072)
        client.disconnect(); client.connect(macID: "first"); client.retry()
        if let delayed { client.receive(id: delayed.0, reply: delayed.1) }
        for _ in 0..<100 where client.state != .completed { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(client.state, .completed)
        XCTAssertEqual(offsets, [0, 131072, 131072, 262144])
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(client.downloadedURL)), contents)
        client.send = nil
    }
    func testDifferentMacCannotResumePreviousMacsTransfer() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("data".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let client = ResumableFileClient(timeout: .milliseconds(40))
        client.connect(macID: "first")
        client.upload(source, parent: "")
        for _ in 0..<100 where client.state != .paused { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(client.state, .paused)
        client.disconnect()
        client.connect(macID: "second")
        var sent = false
        client.send = { _, _ in sent = true }
        client.retry()
        XCTAssertEqual(client.state, .idle)
        XCTAssertFalse(sent)
    }
}
