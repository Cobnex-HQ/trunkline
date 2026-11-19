#if canImport(TrunklineCore)
import TrunklineCore
#endif
import Foundation

#if !targetEnvironment(simulator)
private func receiveRemoteEvent(_ pointer: UnsafePointer<CChar>?) {
    guard let pointer else { return }
    let text = String(cString: pointer)
    Task { @MainActor in RemoteConnection.active?.receive(text) }
}
#endif

@MainActor
final class RemoteConnection {
    static weak var active: RemoteConnection?
    private var ready: CheckedContinuation<Void, Error>?
    private var running = false
    private var stopped = false
    var onLost: ((String) -> Void)?
    func start(_ ticket: RemoteAccessTicket) async throws {
        #if targetEnvironment(simulator)
        throw NSError(domain: "Remote", code: 1, userInfo: [NSLocalizedDescriptionKey: "Away access requires a physical device in this build."])
        #else
        guard Self.active == nil else { throw NSError(domain: "Remote", code: 2, userInfo: [NSLocalizedDescriptionKey: "Away access is already in use in another window or is still closing. Disconnect that Away connection before opening another."]) }
        let config = String(decoding: try JSONEncoder().encode(ticket.config), as: UTF8.self)
        Self.active = self; running = true; stopped = false
        trunkline_p2p_prepare()
        try await withCheckedThrowingContinuation { continuation in
            ready = continuation
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                let code = config.withCString { config in ticket.helper.withCString { helper in
                    trunkline_p2p_session(config, helper, receiveRemoteEvent)
                }}
                Task { @MainActor in
                    running = false
                    if Self.active === self { Self.active = nil }
                    if !stopped { fail("Away connection ended (\(code)). Check that your Mac is online, then retry.") }
                }
            }
        }
        #endif
    }
    func receive(_ text: String) {
        guard !stopped, let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = object["event"] as? String else { return }
        #if DEBUG
        if ["tunnel_ready", "tunnel_lost", "native_error", "setup_retry"].contains(event) {
            print("TRUNKLINE_REMOTE " + event); fflush(stdout)
        }
        #endif
        if event == "tunnel_ready" { let callback = ready; ready = nil; callback?.resume() }
        if event == "tunnel_lost" { fail("The direct connection was interrupted. Tap Connect to retry.") }
        if event == "native_error", let detail = object["details"] as? [String: Any] {
            fail(detail["error"] as? String ?? "Could not establish a direct connection.")
        }
    }
    private func fail(_ message: String) {
        guard !stopped else { return }
        let callback = ready; ready = nil
        // Retire the worker before notifying the model. Native failure and
        // worker exit can arrive together, and only the first is actionable.
        stop()
        if let callback { callback.resume(throwing: NSError(domain: "Remote", code: 1, userInfo: [NSLocalizedDescriptionKey: message])) }
        else { onLost?(message) }
    }
    func stop() {
        stopped = true
        #if !targetEnvironment(simulator)
        if running { trunkline_p2p_stop() }
        #endif
        let callback = ready; ready = nil; callback?.resume(throwing: CancellationError())
    }
}
