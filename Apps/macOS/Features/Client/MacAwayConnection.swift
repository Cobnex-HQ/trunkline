import Foundation
import TrunklineCore

@MainActor
final class MacAwayConnection {
    var onLost: ((String) -> Void)?
    private var process: Process?
    private var output: FileHandle?
    private var pending = Data()
    private var ready: CheckedContinuation<Void, Error>?
    private var deadline: Task<Void, Never>?
    private var directory: URL?
    private var stopped = false
    func start(_ ticket: RemoteAccessTicket) async throws {
        try ticket.validate()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("trunkline-client-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        directory = folder
        let config = folder.appendingPathComponent("peer.json")
        try JSONEncoder().encode(ticket.config).write(to: config, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path)
        let worker = Process(), pipe = Pipe()
        worker.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/TrunklineRemote")
        worker.arguments = ["session", "--config", config.path, "--helper", ticket.helper, "--mode", "dial"]
        worker.standardOutput = pipe
        worker.standardError = FileHandle.nullDevice
        output = pipe.fileHandleForReading
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            if bytes.isEmpty { handle.readabilityHandler = nil; return }
            Task { @MainActor in self?.receive(bytes) }
        }
        worker.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                self.fail(self.ready != nil
                    ? "Couldn’t reach your Mac. Check that it is awake, online and sharing. These networks may block a direct connection. Try connecting again."
                    : "The direct connection ended. Check the remote Mac and retry.")
            }
        }
        process = worker
        do {
            try await withCheckedThrowingContinuation { continuation in
                ready = continuation
                do { try worker.run() } catch { ready = nil; continuation.resume(throwing: error); return }
                deadline = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                    self?.fail("A direct route could not be established. These networks may block peer-to-peer connections.")
                }
            }
        } catch { stop(); throw error }
    }
    private func receive(_ bytes: Data) {
        guard !stopped else { return }
        pending.append(bytes)
        guard pending.count <= 262144 else { fail("Invalid response from the connection helper."); return }
        while let newline = pending.firstIndex(of: 10) {
            let line = pending.prefix(upTo: newline)
            pending.removeSubrange(...newline)
            guard let value = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let event = value["event"] as? String else { continue }
            if event == "tunnel_ready" {
                deadline?.cancel()
                let callback = ready; ready = nil; callback?.resume()
            } else if event == "tunnel_lost" || event == "native_error" {
                fail("The direct connection was interrupted. Reconnect to try again.")
            }
        }
    }
    private func fail(_ message: String) {
        let callback = ready; ready = nil
        if let callback { callback.resume(throwing: NSError(domain: "TrunklineRemote", code: 1, userInfo: [NSLocalizedDescriptionKey: message])) }
        else { onLost?(message) }
        stop()
    }
    func stop() {
        guard !stopped else { return }
        stopped = true
        deadline?.cancel()
        output?.readabilityHandler = nil
        let callback = ready; ready = nil; callback?.resume(throwing: CancellationError())
        if let process, process.isRunning {
            process.interrupt()
            Task {
                try? await Task.sleep(for: .seconds(2))
                if process.isRunning { process.terminate() }
            }
        }
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
    }
    func shutdown() async {
        stop()
        if let process { await ProcessShutdown.finish([process]) }
    }
}
