import Foundation

/// Exercise the actual client before a host has advertised newer file commands.
@main struct FileCompatibilityCheck {
    @MainActor static func main() async throws {
        var failures = 0
        func check(_ value: Bool, _ message: String) {
            if !value { failures += 1; print("FAIL: " + message) }
        }
        let client = ClientFiles()
        var sent: [WireMessage] = []
        client.send = { sent.append($0) }
        defer { client.reset() }
        client.mutate(.createFolder(parent: "", name: "New folder"))
        check(sent.isEmpty && !client.isBusy && client.error != nil,
              "Unadvertised mutation must fail locally without sending an unknown command")
        client.reset(); sent.removeAll()
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1, 2, 3]).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        client.path = "Documents"
        client.upload(source)
        for _ in 0..<100 where client.isBusy && sent.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        check(sent.isEmpty && !client.isBusy && client.error != nil,
              "Unadvertised folder upload must not reach a legacy host or silently upload to root")
        client.reset(); sent.removeAll()
        client.download(.init(name: "file.txt", path: "file.txt", isDirectory: false, size: 3))
        check(sent == [.download(path: "file.txt")], "Legacy downloads remain available")
        sent.removeAll()
        client.cancelTransfer()
        check(sent.isEmpty && client.requiresReconnect && client.isBusy,
              "Legacy cancellation must not send an unknown command or allow another transfer")
        client.handle(.downloadStarted(id: UUID(), name: "file.txt", size: 3))
        try await Task.sleep(for: .milliseconds(50))
        check(sent.isEmpty && client.requiresReconnect,
              "Late legacy replies cannot resume a cancelled transfer")
        client.reset(); sent.removeAll()
        client.upload(source)
        for _ in 0..<100 where sent.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        check(sent == [.beginUpload(name: source.lastPathComponent, size: 3)], "Legacy root upload remains available")
        client.reset(); sent.removeAll()

        // A newer host may advertise an unknown feature; only known capabilities
        // may unlock their corresponding commands, and reset must forget them.
        let payload = Data(#"{"accepted":{"name":"Mac","display":{"width":1920,"height":1080},"fileFeatures":["mutations","cancellation","futureFeature"]}}"#.utf8)
        guard case let .accepted(_, _, features) = try JSONDecoder().decode(WireMessage.self, from: payload) else { fatalError("Expected handshake") }
        client.configure(fileFeatures: features)
        client.path = "Documents"
        check(!client.canUploadHere, "Other advertised features do not unlock folder uploads")
        client.mutate(.createFolder(parent: "Documents", name: "New folder"))
        check(sent.count == 1 && client.mutation != nil, "Advertised mutations remain available")
        if let id = client.mutation {
            check(sent == [.mutateFile(id: id, action: .createFolder(parent: "Documents", name: "New folder"))], "Mutation retains the requested folder and name")
            client.handle(.fileMutationResult(id: id, error: nil))
            client.handle(.fileList(path: "Documents", entries: []))
        }
        client.download(.init(name: "file.txt", path: "file.txt", isDirectory: false, size: 3))
        sent.removeAll(); client.cancelTransfer()
        if let id = client.cancellation {
            check(sent == [.cancelFileTransfer(id: id)], "Advertised cancellation uses the acknowledgement protocol")
            client.handle(.fileTransferCancelled(id: UUID()))
            check(client.isBusy && client.isCancelling, "A mismatched acknowledgement cannot release a transfer")
            client.handle(.fileTransferCancelled(id: id))
            client.handle(.fileList(path: "Documents", entries: []))
            check(!client.isBusy, "Acknowledged cancellation permits further file work")
        } else { check(false, "Modern cancellation must wait for an acknowledgement") }
        client.reset(); sent.removeAll()
        client.mutate(.trash(path: "file.txt"))
        check(sent.isEmpty && client.features.isEmpty && !client.isBusy, "A subsequent legacy host cannot inherit the previous host’s features")

        let stalled = ClientFiles(operationTimeout: .milliseconds(30))
        var stalledMessages: [WireMessage] = []
        stalled.send = { stalledMessages.append($0) }
        defer { stalled.reset() }
        stalled.download(.init(name: "stalled", path: "stalled", isDirectory: false, size: 3))
        for _ in 0..<100 where !stalled.requiresReconnect { try await Task.sleep(for: .milliseconds(10)) }
        check(stalled.requiresReconnect && stalledMessages == [.download(path: "stalled")],
              "Legacy transfer timeout blocks reuse without sending unsupported cancellation")
        guard failures == 0 else { exit(1) }
        print("PASS: legacy Files compatibility and cancellation isolation")
    }
}
