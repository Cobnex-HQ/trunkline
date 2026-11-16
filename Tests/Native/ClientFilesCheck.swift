import Foundation

/// Real temporary-file I/O through the client protocol boundary. No transport or disk mocks.
@main struct ClientFilesCheck {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Trunkline-client-files-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var failures = 0
        func check(_ passed: Bool, _ message: String) {
            if !passed { failures += 1; print("FAIL: " + message) }
        }
        func waitFor(_ condition: () -> Bool) async {
            for _ in 0..<300 {
                if condition() { return }
                try? await Task.sleep(for: .milliseconds(10))
            }
            check(false, "Client disk operation completed within test deadline")
        }
        let client = ClientFiles()
        client.configure(fileFeatures: FileFeature.allCases.map(\.rawValue))
        var messages: [WireMessage] = []
        client.send = { messages.append($0) }
        defer { client.reset() }
        // File open and each chunk must yield the UI actor, including fast local files.
        let source = root.appendingPathComponent("source.bin")
        let bytes = Data((0..<300_000).map { UInt8($0 % 251) })
        try bytes.write(to: source)
        client.upload(source)
        check(client.isBusy, "Opening an upload immediately reserves the transfer")
        check(messages.isEmpty, "Opening a file must release the UI actor before sending")
        await waitFor { !messages.isEmpty }
        check(messages == [.beginUpload(name: "source.bin", size: 300_000)], "Upload size and name")
        messages.removeAll()
        let uploadID = UUID()
        client.handle(.uploadReady(id: uploadID))
        var uploaded = Data()
        while uploaded.count < bytes.count {
            check(messages.isEmpty, "Reading a chunk must release the UI actor before sending")
            await waitFor { !messages.isEmpty }
            guard case let .uploadChunk(id, offset, chunk) = messages.removeFirst() else { fatalError("Expected upload bytes") }
            check(id == uploadID && offset == uploaded.count, "Upload chunks preserve identity and order")
            uploaded.append(chunk)
            if uploaded.count < bytes.count {
                client.handle(.transferProgress(id: uploadID, received: Int64(uploaded.count), total: 300_000))
            }
        }
        check(uploaded == bytes, "Multi-chunk upload preserves every byte")
        client.handle(.uploadComplete(id: uploadID))
        await waitFor { messages.contains(.listFiles(path: "")) }
        client.handle(.fileList(path: "", entries: []))
        check(!client.isBusy && client.error == nil, "Upload closes before listing resumes")

        // Actual download creation, ordered writes, final synchronization and reset cleanup.
        messages.removeAll()
        client.download(RemoteFile(name: "download.bin", path: "download.bin", isDirectory: false, size: 300_000))
        messages.removeAll()
        let downloadID = UUID()
        client.handle(.downloadStarted(id: downloadID, name: "download.bin", size: 300_000))
        check(messages.isEmpty, "Creating a download must release the UI actor")
        await waitFor { !messages.isEmpty }
        for offset in stride(from: 0, to: bytes.count, by: 100_000) {
            check(messages.removeFirst() == .requestChunk(id: downloadID, offset: Int64(offset)), "Download requests follow completed disk writes")
            let last = offset == 200_000
            client.handle(.downloadChunk(id: downloadID, offset: Int64(offset), bytes: bytes.subdata(in: offset..<(offset + 100_000)), last: last))
            check(messages.isEmpty && client.downloadedURL == nil, "Writing and finishing a download must release the UI actor")
            await waitFor { last ? client.downloadedURL != nil : !messages.isEmpty }
        }
        guard let destination = client.downloadedURL else { fatalError("Missing completed download") }
        check(try Data(contentsOf: destination) == bytes, "Multi-chunk download preserves every byte")
        check(!client.isBusy && client.error == nil, "Download finishes without leaving a busy state")
        client.reset()
        client.configure(fileFeatures: FileFeature.allCases.map(\.rawValue))
        await waitFor { !FileManager.default.fileExists(atPath: destination.deletingLastPathComponent().path) }

        // Reset before the open completion must not send an old beginUpload into a new connection.
        messages.removeAll()
        client.upload(source)
        client.reset()
        client.configure(fileFeatures: FileFeature.allCases.map(\.rawValue))
        messages.removeAll()
        let next = root.appendingPathComponent("next.txt")
        try Data("new session".utf8).write(to: next)
        client.upload(next)
        await waitFor { !messages.isEmpty }
        check(messages == [.beginUpload(name: "next.txt", size: 11)], "Disconnect discards the old open completion")
        messages.removeAll()
        client.handle(.uploadReady(id: UUID()))
        client.cancelTransfer()
        guard let cancelID = client.cancellation else { fatalError("Cancellation missing") }
        messages.removeAll()
        client.handle(.fileTransferCancelled(id: cancelID))
        client.handle(.fileList(path: "", entries: []))
        client.upload(next)
        await waitFor { messages.contains(.beginUpload(name: "next.txt", size: 11)) }
        check(!messages.contains { if case .uploadChunk = $0 { return true }; return false }, "Cancelled read cannot send bytes into the next transfer")
        check(client.error == nil && client.cancellation == nil, "Next transfer survives old disk completion")
        client.reset()
        client.configure(fileFeatures: FileFeature.allCases.map(\.rawValue))

        // A local open failure has never begun a remote upload and needs no cancellation round trip.
        messages.removeAll()
        client.upload(root.appendingPathComponent("missing.txt"))
        await waitFor { !client.isBusy }
        check(client.error != nil && messages.isEmpty, "Missing file fails locally and releases transfer state")
        client.reset()
        client.configure(fileFeatures: FileFeature.allCases.map(\.rawValue))

        // Cancellation while a final disk write is queued cannot publish a stale file URL.
        // A subsequent upload acts as the ordered disk-queue barrier for this check.
        messages.removeAll()
        let cancelledName = "cancel-" + UUID().uuidString + ".bin"
        client.download(RemoteFile(name: cancelledName, path: cancelledName, isDirectory: false, size: 3))
        messages.removeAll()
        let cancelledDownload = UUID()
        client.handle(.downloadStarted(id: cancelledDownload, name: cancelledName, size: 3))
        await waitFor { messages.contains(.requestChunk(id: cancelledDownload, offset: 0)) }
        client.handle(.downloadChunk(id: cancelledDownload, offset: 0, bytes: Data([1, 2, 3]), last: true))
        client.cancelTransfer()
        guard let downloadCancellation = client.cancellation else { fatalError("Download cancellation missing") }
        client.handle(.fileTransferCancelled(id: downloadCancellation))
        client.handle(.fileList(path: "", entries: []))
        messages.removeAll()
        client.upload(next)
        await waitFor { !messages.isEmpty }
        check(client.downloadedURL == nil && client.transferName == "next.txt", "Cancelled final write cannot publish a file or clear the next transfer")
        check(messages == [.beginUpload(name: "next.txt", size: 11)], "No stale download requests escape cancellation")
        let temporaryFolders = try FileManager.default.contentsOfDirectory(at: FileManager.default.temporaryDirectory, includingPropertiesForKeys: nil)
        check(!temporaryFolders.contains { FileManager.default.fileExists(atPath: $0.appendingPathComponent(cancelledName).path) },
              "Cancellation removes a completed file whose UI result was discarded")
        client.reset()
        client.configure(fileFeatures: FileFeature.allCases.map(\.rawValue))
        guard failures == 0 else { exit(1) }
        print("PASS: client deferred I/O, exact multi-chunk bytes, cleanup, disconnect and cancellation races")
    }
}
