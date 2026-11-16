#if canImport(TrunklineCore)
import TrunklineCore
#endif
import Foundation
import Combine

@MainActor
final class AwayAccessHost: ObservableObject {
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "away-access-enabled")
    @Published private(set) var status = "Away access is off"
    @Published private(set) var ticket: RemoteAccessTicket?
    @Published private(set) var busy = false
    private var worker: Process?
    private var setup: Task<Void, Never>?
    private var generation = UUID()
    private var buffer = Data()
    private let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Trunkline/Remote", isDirectory: true)
    private var executable: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/TrunklineRemote") }

    func enable() { enabled = true; UserDefaults.standard.set(true, forKey: "away-access-enabled"); start() }
    func disable() { enabled = false; UserDefaults.standard.set(false, forKey: "away-access-enabled"); stop(); status = "Away access is off" }
    func start() {
        guard enabled, setup == nil, worker == nil else { return }
        busy = true; status = "Preparing away access…"
        let id = UUID(); generation = id
        setup = Task { [weak self] in
            guard let self else { return }
            do {
                if !FileManager.default.fileExists(atPath: directory.path) {
                    try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
                    _ = try await command(["pair", directory.path])
                }
                try Task.checkCancellation()
                let helperURL = directory.appendingPathComponent("helper.txt")
                var helper = (try? String(contentsOf: helperURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let saved = helper {
                    status = "Checking connection setup…"
                    if (try? await command(["check-helper", "--helper", saved, "--seconds", "15"])) == nil { helper = nil }
                }
                if helper == nil {
                    status = "Finding a connection setup helper…"
                    let lines = try await command(["discover", "--seconds", "60"])
                    guard let reservation = lines.first(where: { $0["event"] as? String == "helper_reserved" }),
                          let details = reservation["details"] as? [String: Any],
                          let accepted = details["helper"] as? String else { throw failure("No setup helper is available. Retry shortly.") }
                    helper = accepted
                    // Prefer the accepted peer's QUIC listener when advertised and verified.
                    if let candidate = lines.first(where: { ($0["details"] as? [String: Any])?["address"] as? String == accepted }),
                       let candidateDetails = candidate["details"] as? [String: Any],
                       let addresses = candidateDetails["advertised_addresses"] as? [String],
                       let peer = details["peer"] as? String,
                       let quic = addresses.first(where: { $0.contains("/quic-v1") && !$0.contains("/webtransport") && $0.hasPrefix("/ip4/") }) {
                        let address = quic.contains("/p2p/") ? quic : quic + "/p2p/" + peer
                        if (try? await command(["check-helper", "--helper", address, "--seconds", "15"])) != nil { helper = address }
                    }
                    try helper!.write(to: helperURL, atomically: true, encoding: .utf8)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: helperURL.path)
                }
                try Task.checkCancellation()
                guard generation == id, let helper else { return }
                let config = try JSONDecoder().decode(RemoteAccessTicket.Config.self, from: Data(contentsOf: directory.appendingPathComponent("phone.json")))
                let ticket = RemoteAccessTicket(config: config, helper: helper); try ticket.validate()
                launch(helper: helper, ticket: ticket, generation: id)
                setup = nil
            } catch {
                guard generation == id else { return }
                busy = false; setup = nil; status = error.localizedDescription
            }
        }
    }
    func stop() {
        generation = UUID(); setup?.cancel(); setup = nil
        if let worker, worker.isRunning { worker.interrupt() }
        worker = nil; ticket = nil; busy = false; buffer.removeAll()
        if enabled { status = "Away access paused" }
    }
    private func launch(helper: String, ticket: RemoteAccessTicket, generation id: UUID) {
        let process = Process(); let output = Pipe()
        process.executableURL = executable
        process.arguments = ["session", "--config", directory.appendingPathComponent("mac.json").path, "--helper", helper, "--mode", "listen"]
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            Task { @MainActor in
                guard let self, self.generation == id else { return }
                self.buffer.append(data)
                while let newline = self.buffer.firstIndex(of: 10) {
                    let line = self.buffer.prefix(upTo: newline); self.buffer.removeSubrange(...newline)
                    guard let value = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let event = value["event"] as? String else { continue }
                    switch event {
                    case "remote_waiting": self.ticket = ticket; self.busy = false; self.status = "Ready for direct connections"
                    case "tunnel_ready": self.status = "Device connected directly"
                    case "tunnel_lost": self.status = "Waiting for your device to reconnect"
                    case "setup_retry": if self.ticket == nil { self.status = "Retrying connection setup…" }
                    default: break
                    }
                }
                if self.buffer.count > 65536 { self.buffer.removeAll() }
            }
        }
        process.terminationHandler = { [weak self] _ in
            output.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                guard let self, self.generation == id else { return }
                self.worker = nil; self.ticket = nil; self.busy = false
                self.status = "Away access stopped. Retry to reconnect."
            }
        }
        do { try process.run(); worker = process; status = "Opening connection setup…" }
        catch { busy = false; status = error.localizedDescription }
    }
    private func command(_ args: [String]) async throws -> [[String: Any]] {
        let executable = executable
        return try await Task.detached {
            let process = Process(); let output = Pipe()
            process.executableURL = executable; process.arguments = args
            process.standardOutput = output; process.standardError = FileHandle.nullDevice
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw NSError(domain: "Remote", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Connection setup is unavailable. Retry shortly."]) }
            return data.split(separator: 10).compactMap { try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] }
        }.value
    }
    private func failure(_ message: String) -> Error { NSError(domain: "Remote", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
