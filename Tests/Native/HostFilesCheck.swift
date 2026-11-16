import Foundation

/// Standalone integration check against the actual Mac file service and temporary files.
@main struct HostFilesCheck {
    @MainActor static func main() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Trunkline-file-check-" + UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let service = HostFiles(root: root)
            var failures = 0
            func check(_ passed: Bool, _ message: String) {
                if !passed { failures += 1; print("FAIL: " + message) }
            }
            func request(_ message: WireMessage) async -> WireMessage {
                var returned = false
                var deferred = false
                let reply: WireMessage = await withCheckedContinuation { continuation in
                    let handled = service.handle(message) {
                        deferred = returned
                        continuation.resume(returning: $0)
                    }
                    precondition(handled, "File operation not routed")
                    returned = true
                }
                check(deferred, "File work must release the calling UI actor before replying")
                return reply
            }
            let contents = Data("A real, ordered transfer through the file service.".utf8)
            let ready = await request(.beginUpload(name: "sample.txt", size: Int64(contents.count)))
            guard case let .uploadReady(id) = ready else { fatalError("Upload did not start") }
            let complete = await request(.uploadChunk(id: id, offset: 0, bytes: contents))
            check(complete == .uploadComplete(id: id), "Upload acknowledgement")
            check(try Data(contentsOf: root.appendingPathComponent("sample.txt")) == contents, "Uploaded bytes")
            let listing = await request(.listFiles(path: ""))
            if case let .fileList(_, files) = listing { check(files.map(\.name) == ["sample.txt"], "Directory contents") }
            else { check(false, "Directory reply") }
            let start = await request(.download(path: "sample.txt"))
            guard case let .downloadStarted(downloadID, _, _) = start else { fatalError("Download did not start") }
            let chunk = await request(.requestChunk(id: downloadID, offset: 0))
            check(chunk == .downloadChunk(id: downloadID, offset: 0, bytes: contents, last: true), "Downloaded bytes")
            let escaped = await request(.listFiles(path: "../"))
            if case let .operationError(_, context) = escaped { check(context?.domain == .files, "File service labels file errors") }
            else { check(false, "Folder scope must remain confined") }
            // Rejected input must not change the user's clipboard.
            var clipboardReply: WireMessage?
            _ = service.handle(.setClipboard(String(repeating: "x", count: 65537))) { clipboardReply = $0 }
            if case let .operationError(_, context) = clipboardReply { check(context?.domain == .clipboard, "Clipboard rejection is separately scoped") }
            else { check(false, "Oversized clipboard input is rejected") }

            let client = ClientFiles()
            client.configure(fileFeatures: FileFeature.allCases.map(\.rawValue))
            client.send = { [weak client] message in
                _ = service.handle(message) { [weak client] reply in _ = client?.handle(reply) }
            }
            defer { client.send = nil; client.reset() }
            func finishClientOperation() async {
                for _ in 0..<200 {
                    if !client.isBusy && !client.isLoading { return }
                    try? await Task.sleep(for: .milliseconds(10))
                }
                check(false, "Client operation completed within its local test deadline")
            }
            let documents = root.appendingPathComponent("Documents")
            try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
            let source = root.appendingPathComponent("source")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            let uploadURL = source.appendingPathComponent("in-folder.txt")
            try contents.write(to: uploadURL)
            client.path = "Documents"
            client.upload(uploadURL)
            await finishClientOperation()
            check(FileManager.default.fileExists(atPath: documents.appendingPathComponent("in-folder.txt").path), "Upload uses the folder visible on the client")
            check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("in-folder.txt").path), "Nested upload does not land in the shared root")

            let cancelledURL = source.appendingPathComponent("cancelled.txt")
            try Data(repeating: 42, count: 256 * 1024).write(to: cancelledURL)
            client.upload(cancelledURL)
            client.cancelTransfer()
            await finishClientOperation()
            let nextURL = source.appendingPathComponent("after-cancel.txt")
            try contents.write(to: nextURL)
            client.upload(nextURL)
            await finishClientOperation()
            check(client.error == nil, "Cancelled transfer releases the host for the next upload")
            check(FileManager.default.fileExists(atPath: documents.appendingPathComponent("after-cancel.txt").path), "Next upload succeeds after cancellation")
            check(!FileManager.default.fileExists(atPath: documents.appendingPathComponent("cancelled.txt").path), "Cancellation before chunks does not commit a file")
            check(!(try FileManager.default.contentsOfDirectory(atPath: documents.path)).contains(where: { $0.hasSuffix(".part") }), "Cancellation removes partial data")

            // A silent transport exercises stalled-operation recovery, not a mocked file service.
            let silent = ClientFiles(operationTimeout: .milliseconds(40), cancellationTimeout: .milliseconds(40))
            silent.configure(fileFeatures: FileFeature.allCases.map(\.rawValue))
            silent.list("Documents")
            try? await Task.sleep(for: .milliseconds(150))
            check(!silent.isLoading && silent.error != nil, "A silent host cannot leave folder loading forever")
            silent.reset()
            silent.configure(fileFeatures: FileFeature.allCases.map(\.rawValue))
            silent.upload(cancelledURL)
            try? await Task.sleep(for: .milliseconds(200))
            check(silent.requiresReconnect && silent.transferName == nil && silent.error != nil, "Missing transfer/cancellation replies produce explicit reconnect recovery")
            silent.reset()
            check(!silent.isBusy && !silent.requiresReconnect, "Reconnect clears expired transfer state")
            let isolated = ClientFiles()
            isolated.configure(fileFeatures: FileFeature.allCases.map(\.rawValue))
            defer { isolated.reset() }
            isolated.upload(cancelledURL)
            let unrelated = try JSONDecoder().decode(WireMessage.self, from: Data(#"{"operationError":{"_0":"Terminal unavailable","context":{"domain":"terminal"}}}"#.utf8))
            check(!isolated.handle(unrelated), "Files does not consume another feature’s error")
            check(isolated.transferName != nil && isolated.cancellation == nil && isolated.error == nil,
                  "A terminal failure cannot cancel an upload")
            isolated.cancelTransfer()
            check(!isolated.handle(unrelated), "Cancellation barrier cannot swallow another feature’s error")
            _ = isolated.handle(.operationError("Clipboard too large", context: .init(.clipboard)))
            check(isolated.clipboardError == "Clipboard too large" && isolated.error == nil && isolated.isCancelling,
                  "Clipboard error remains local while cancellation is pending")
            _ = isolated.handle(.clipboard("Recovered"))
            check(isolated.clipboardError == nil, "Successful clipboard reply clears its previous error")
            let stalled = ClientFiles(operationTimeout: .milliseconds(40), cancellationTimeout: .seconds(2))
            stalled.configure(fileFeatures: FileFeature.allCases.map(\.rawValue))
            defer { stalled.reset() }
            stalled.upload(cancelledURL)
            try? await Task.sleep(for: .milliseconds(120))
            guard let cancellationID = stalled.cancellation else { fatalError("Stalled transfer did not request cancellation") }
            _ = stalled.handle(.fileTransferCancelled(id: UUID()))
            check(stalled.isCancelling, "Unrelated cancellation reply cannot release the pending transfer")
            _ = stalled.handle(.fileTransferCancelled(id: cancellationID))
            check(!stalled.isCancelling && stalled.error == "The transfer stopped responding. Try again.", "Acknowledged cancellation preserves the actionable timeout notice")
            guard failures == 0 else { exit(1) }
            print("PASS: asynchronous files, transfer bytes/order, folder scope, nested upload and cancellation recovery")
        } catch { print("FAIL: \(error)"); exit(1) }
    }
}
