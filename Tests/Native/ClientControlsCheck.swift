import Foundation

/// Exercises the actual client state against a silent transport and encoded replies.
@main struct ClientControlsCheck {
    @MainActor static func main() async throws {
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            if !condition { failures += 1; print("FAIL: " + message) }
        }
        let client = ClientControls()
        defer { client.reset() }
        var refreshRequests = 0
        client.send = { if case .requestControls = $0 { refreshRequests += 1 } }
        client.refresh(); client.refresh(); client.refresh()
        check(refreshRequests == 1, "Polling coalesces while a snapshot is outstanding")
        try await Task.sleep(for: .seconds(11))
        // The consumer-visible recovery state must replace perpetual initial loading.
        check(client.snapshot == nil && client.refreshError != nil && !client.isRefreshing,
              "An unresponsive Mac produces retry recovery instead of endless loading")
        client.refresh()
        check(refreshRequests == 2 && client.isRefreshing, "Refresh is available after timeout")
        let state = MacControlSnapshot(apps: [], windows: [], displays: [], volume: 0.5,
                                       muted: false, accessibility: true, frontmostApp: "Finder")
        var parser = PacketParser()
        for message in try parser.append(PacketCodec.encode(.controls(state))) { _ = client.handle(message) }
        check(client.snapshot == state && client.refreshError == nil && !client.isRefreshing,
              "A real snapshot clears timeout recovery")

        client.error = "An earlier action failed"
        client.refresh()
        _ = client.handle(.controls(state))
        check(client.error != nil, "Background refresh does not erase an action failure")
        client.reset()
        check(client.snapshot == nil && client.error == nil && client.refreshError == nil && !client.isRefreshing,
              "Disconnect clears loading, errors and snapshots")
        var sentAction = false
        client.send = { if case .control = $0 { sentAction = true } }
        client.perform(.system(.sleep))
        check(!sentAction && client.pending == nil && client.error != nil,
              "Disruptive action cannot leave the client without confirmation")
        client.perform(.power(.restart), confirmed: true)
        check(!sentAction && client.pending == nil, "Older hosts cannot receive unadvertised power commands")
        var capable = state
        capable.power = MacPowerCapability(actions: ["restart"], authorizationRequired: false)
        _ = client.handle(.controls(capable))
        client.perform(.power(.shutDown), confirmed: true)
        check(!sentAction && client.pending == nil, "An unavailable power action cannot be sent")
        client.perform(.power(.restart))
        check(!sentAction && client.pending == nil, "Advertised power actions still require confirmation")
        client.perform(.power(.restart), confirmed: true)
        check(sentAction && client.pending != nil && client.error == nil, "A confirmed supported power request reaches the transport")
        if let id = client.pending { _ = client.handle(.controlResult(MacControlResult(id: id))) }
        check(client.pending == nil && client.error == nil, "Power acknowledgement releases the pending control")
        guard failures == 0 else { exit(1) }
        print("PASS: controls refresh/timeout recovery, disconnect reset, confirmation enforcement and power capability gating")
    }
}
