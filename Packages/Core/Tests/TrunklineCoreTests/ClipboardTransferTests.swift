import XCTest
@testable import TrunklineCore

@MainActor
final class ClipboardTransferTests: XCTestCase {
    func testCopyWaitsForMacAndDoesNotOverwriteANewerLocalCopy() {
        let client = ClipboardTransfer()
        var local = "old", revision = 1
        var requests: [WireMessage] = []
        client.send = { requests.append($0) }
        client.localRevision = { revision }
        client.writeLocal = { local = $0; revision += 1 }
        client.activate()
        client.copyFromMac()
        XCTAssertTrue(client.isBusy)
        XCTAssertEqual(local, "old")
        local = "new local copy"; revision += 1
        client.receive("remote")
        XCTAssertEqual(local, "new local copy")
        XCTAssertFalse(client.isBusy)
        XCTAssertNotNil(client.error)
        client.copyFromMac()
        client.receive("remote")
        XCTAssertEqual(local, "remote")
        XCTAssertEqual(requests.count, 2)
        XCTAssertNotNil(client.feedback)
        client.reset()
    }

    func testPasteRequiresMatchingAcknowledgementAndRejectsOversizedUnicode() {
        let client = ClipboardTransfer()
        var requests: [WireMessage] = []
        client.send = { requests.append($0) }
        client.activate()
        client.pasteToMac(String(repeating: "😀", count: 32769))
        XCTAssertTrue(requests.isEmpty)
        XCTAssertNotNil(client.error)
        client.pasteToMac("hello")
        XCTAssertTrue(client.isBusy)
        XCTAssertNil(client.feedback)
        client.pasteToMac("duplicate")
        XCTAssertEqual(requests.count, 1)
        client.receive("different")
        XCTAssertNotNil(client.error)
        XCTAssertNil(client.feedback)
        client.pasteToMac("hello")
        client.receive("hello")
        XCTAssertNil(client.error)
        XCTAssertNotNil(client.feedback)
        client.reset()
    }

    func testSyncRequiresConsentAndDoesNotEchoReceivedText() {
        let client = ClipboardTransfer()
        var local = "private", revision = 0, reads = 0
        var requests: [WireMessage] = []
        client.send = { requests.append($0) }
        client.readLocal = { reads += 1; return local }
        client.localRevision = { revision }
        client.writeLocal = { local = $0; revision += 1 }
        client.activate()
        client.poll()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(reads, 0)
        client.mode = .fromMac
        client.poll()
        client.receive("Mac text")
        XCTAssertEqual(local, "Mac text")
        client.mode = .bothDirections
        client.poll()
        XCTAssertEqual(reads, 0, "Our own clipboard write must not be sent back")
        client.receive("Mac text")
        local = "new device text"; revision += 1
        client.poll()
        guard case .setClipboard("new device text") = requests.last else { return XCTFail("Local changes should sync after consent") }
        client.receive("new device text")
        client.reset()
        client.poll()
        XCTAssertEqual(reads, 1, "Background/disconnect must stop clipboard access")
    }

    func testWindowActivationDoesNotOverwriteAnExistingDeviceClipboard() {
        let client = ClipboardTransfer()
        var local = "copied in another window", revision = 1
        client.localRevision = { revision }
        client.writeLocal = { local = $0; revision += 1 }
        client.mode = .bothDirections
        client.activate(); client.poll(); client.receive("old Mac text")
        XCTAssertEqual(local, "copied in another window")
        client.poll(); client.receive("new Mac text")
        XCTAssertEqual(local, "new Mac text")
        client.pause()
        local = "copied while inactive"; revision += 1
        client.activate(); client.poll(); client.receive("different Mac text")
        XCTAssertEqual(local, "copied while inactive")
        client.reset()
    }

    func testTimeoutQuarantinesLateLegacyRepliesUntilReconnect() async throws {
        let client = ClipboardTransfer(timeout: .milliseconds(20))
        var copied: [String] = [], requests = 0
        client.writeLocal = { copied.append($0) }
        client.send = { _ in requests += 1 }
        client.activate()
        client.copyFromMac()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(client.isBusy)
        XCTAssertTrue(client.requiresReconnect)
        client.receive("late")
        client.copyFromMac()
        XCTAssertTrue(copied.isEmpty)
        XCTAssertEqual(requests, 1)
        client.reset(); client.activate(); client.copyFromMac(); client.receive("fresh")
        XCTAssertEqual(copied, ["fresh"])
        client.reset()
    }

    func testClipboardConsentIsScopedToMacAndOffByDefault() {
        let suite = "clipboard-preferences-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MacPreferencesStore(defaults: defaults)
        XCTAssertEqual(store.load("a").clipboard, .off)
        var a = store.load("a"); a.clipboard = .fromMac
        store.save(a, for: "a")
        XCTAssertEqual(store.load("a").clipboard, .fromMac)
        XCTAssertEqual(store.load("b").clipboard, .off)
    }
}
