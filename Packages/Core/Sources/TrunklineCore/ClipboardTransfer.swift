import Foundation
import Combine

/// Serializes the legacy clipboard protocol. A timeout quarantines replies
/// until reconnect because older hosts do not attach request identifiers.
@MainActor
public final class ClipboardTransfer: ObservableObject {
    @Published public private(set) var text = ""
    @Published public private(set) var isBusy = false
    @Published public private(set) var requiresReconnect = false
    @Published public private(set) var error: String?
    @Published public private(set) var feedback: String?
    @Published public var mode: ClipboardSyncMode = .off {
        didSet { revision = localRevision(); schedulePolling() }
    }
    public var send: ((WireMessage) -> Void)?
    public var localRevision: () -> Int = { 0 }
    public var readLocal: () -> String? = { nil }
    public var writeLocal: (String) -> Void = { _ in }
    private enum Operation { case copy(revision: Int, automatic: Bool), paste(String) }
    private var pending: Operation?
    private var active = false
    private var revision = 0
    private var lastRemote: String?
    private let timeout: Duration
    private var deadline: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var generation = UUID()
    public init(timeout: Duration = .seconds(8)) { self.timeout = timeout }
    public func activate() {
        active = true
        revision = localRevision()
        schedulePolling()
    }
    public func pause() { active = false; pollTask?.cancel(); pollTask = nil }
    public func copyFromMac() { requestCopy(automatic: false) }
    private func requestCopy(automatic: Bool) {
        guard active, !isBusy, !requiresReconnect else { return }
        begin(.copy(revision: localRevision(), automatic: automatic))
        send?(.requestClipboard)
    }
    public func pasteToMac(_ value: String) {
        guard active, !isBusy, !requiresReconnect else { return }
        guard value.utf16.count <= 65536 else { error = "Text is limited to 65,536 characters."; return }
        begin(.paste(value))
        send?(.setClipboard(value))
    }
    public func poll() {
        guard active, mode != .off, !isBusy, !requiresReconnect else { return }
        let current = localRevision()
        if mode == .bothDirections, current != revision {
            revision = current
            if let value = readLocal() { pasteToMac(value); return }
        }
        requestCopy(automatic: true)
    }
    public func receive(_ value: String) {
        guard let operation = pending, !requiresReconnect else { return }
        finish()
        guard active else { return }
        guard value.utf16.count <= 65536 else { fail("The Mac clipboard is too large."); return }
        text = value
        switch operation {
        case let .paste(sent):
            guard value == sent else { fail("The Mac did not confirm the clipboard text. Try again."); return }
            lastRemote = value
            feedback = "Copied to Mac clipboard"
        case let .copy(expected, automatic):
            guard !automatic || mode != .off else { return }
            guard localRevision() == expected else {
                if !automatic { error = "Your clipboard changed. Copy from Mac again." }
                return
            }
            if !automatic || value != lastRemote {
                // Do not erase a local clipboard just because the Mac has no text.
                if !value.isEmpty { writeLocal(value); revision = localRevision() }
            }
            lastRemote = value
            if !automatic { feedback = value.isEmpty ? "The Mac clipboard has no text" : "Copied from Mac" }
        }
    }
    public func fail(_ message: String) { finish(); error = message; feedback = nil }
    public func reset() {
        pause(); finish(); text = ""; error = nil; feedback = nil
        requiresReconnect = false; lastRemote = nil
    }
    private func begin(_ operation: Operation) {
        pending = operation; isBusy = true; error = nil; feedback = nil
        let id = UUID(); generation = id
        deadline = Task { [weak self, timeout] in
            do { try await Task.sleep(for: timeout) } catch { return }
            guard let self, self.generation == id else { return }
            self.finish(); self.requiresReconnect = true
            self.error = "Clipboard timed out. Reconnect to try again."
        }
    }
    private func finish() {
        generation = UUID(); deadline?.cancel(); deadline = nil
        pending = nil; isBusy = false
    }
    private func schedulePolling() {
        pollTask?.cancel(); pollTask = nil
        guard active, mode != .off else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                self?.poll()
            }
        }
    }
    deinit { deadline?.cancel(); pollTask?.cancel() }
}
