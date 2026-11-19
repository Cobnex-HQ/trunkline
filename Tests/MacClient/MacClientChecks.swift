import Foundation
import Network

@main struct MacClientChecks {
    @MainActor static func main() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        var peer: SecureChannel?
        var authenticated = false
        listener.newConnectionHandler = { connection in
            MainActor.assumeIsolated {
                let channel = SecureChannel(connection: connection)
                peer = channel
                channel.onMessage = { message in
                    if case .authenticate("fixture-passcode") = message {
                        authenticated = true
                        channel.send(.accepted(name: "Fixture Mac", display: .init(width: 3024, height: 1964)))
                    }
                    if case .ping = message { channel.send(.pong) }
                }
                channel.start()
            }
        }
        var listening = false
        listener.stateUpdateHandler = { state in
            MainActor.assumeIsolated { if case .ready = state { listening = true } }
        }
        listener.start(queue: .main)
        defer { listener.cancel(); peer?.close() }
        for _ in 0..<100 where !listening { try await Task.sleep(for: .milliseconds(20)) }
        guard listening, let port = listener.port, port.rawValue != 0 else { fatalError("Fixture listener failed") }
        let model = MacClientConnection(makeChannel: { _ in SecureChannel(connection: NWConnection(host: "127.0.0.1", port: port, using: .tcp)) })
        var disconnects = 0
        model.onDisconnect = { disconnects += 1 }
        let pairing = try PairingDetails(host: "127.0.0.1", port: port.rawValue, fingerprint: String(repeating: "a", count: 64))
        model.connect(pairing: pairing, passcode: "fixture-passcode")
        precondition(disconnects == 0, "Starting authentication must not tear down the prepared away tunnel")
        for _ in 0..<200 where model.phase != .connected { try await Task.sleep(for: .milliseconds(20)) }
        precondition(authenticated && model.phase == .connected && model.name == "Fixture Mac")
        precondition(model.display.width == 3024 && model.display.height == 1964)
        peer?.send(.failure("Already controlled by another device", cause: .hostBusy))
        for _ in 0..<100 where model.phase != .disconnected { try await Task.sleep(for: .milliseconds(20)) }
        precondition(model.phase == .disconnected && model.error == "Already controlled by another device")
        model.connect(pairing: pairing, passcode: "fixture-passcode")
        model.disconnect()
        try await Task.sleep(for: .milliseconds(100))
        precondition(model.phase == .disconnected, "A late callback must not revive a cancelled connection")
        print("PASS: authenticated Mac companion connection, display metadata, admission rejection and cancellation")
    }
}
