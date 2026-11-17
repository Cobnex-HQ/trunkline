import Foundation

@main struct RemoteAwakeClientCheck {
    @MainActor static func main() throws {
        let client = ClientControls()
        var requests: [MacControlRequest] = []
        client.send = { if case let .control(request) = $0 { requests.append(request) } }
        let old = MacControlSnapshot(apps: [], windows: [], displays: [], volume: nil, muted: nil,
                                     accessibility: false, frontmostApp: "Mac")
        let decoded = try JSONDecoder().decode(MacControlSnapshot.self, from: JSONEncoder().encode(old))
        _ = client.handle(.controls(decoded))
        client.perform(.keepAwake(.system))
        precondition(requests.isEmpty && client.pending == nil, "Older hosts must not receive unknown actions")
        var state = old
        state.keepAwake = MacAwakeState(mode: .off, sessionActive: true, awayAccessActive: false, requiresLocalChange: true)
        _ = client.handle(.controls(state))
        client.perform(.keepAwake(.system))
        precondition(requests.isEmpty, "Local recovery must not trigger remote authorization")
        state.keepAwake = MacAwakeState(mode: .off, sessionActive: true, awayAccessActive: false, requiresLocalChange: false)
        _ = client.handle(.controls(state))
        client.perform(.keepAwake(.lidClosed))
        precondition(requests.isEmpty)
        client.perform(.keepAwake(.system))
        precondition(requests.count == 1 && requests[0].action == .keepAwake(.system))
        var parser = PacketParser()
        let messages = try parser.append(PacketCodec.encode(.control(requests[0])))
        guard case let .control(roundTrip) = messages.first else { fatalError("Missing serialized control") }
        precondition(roundTrip.action == .keepAwake(.system))
        _ = client.handle(.controlResult(MacControlResult(id: requests[0].id)))
        precondition(client.pending == nil)
        client.reset()
        print("PASS: legacy-host compatibility, recovery guard, closed-lid rejection and awake wire round trip")
    }
}
