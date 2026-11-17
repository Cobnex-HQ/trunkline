import AppKit
import ServiceManagement

@main struct RemoteAwakeCheck {
    @MainActor static func main() async throws {
        let manager = KeepAwakeManager(loginStatus: { .notRegistered })
        guard !manager.needsRecovery else { throw NSError(domain: "Existing local recovery needs attention", code: 1) }
        defer { try? manager.applyRemotely(.off); manager.setSessionActive(false) }
        try manager.applyRemotely(.system)
        precondition(manager.remoteState.mode == .system)
        manager.setSessionActive(true)
        try manager.applyRemotely(.off)
        precondition(manager.remoteState.sessionActive, "Automatic mode must retain the live connection's assertion")
        precondition(manager.remoteState.mode == .off)
        do {
            try manager.applyRemotely(.lidClosed)
            fatalError("Remote requests must never invoke local administrator approval")
        } catch { precondition(manager.mode == .off) }
        try manager.applyRemotely(.systemAndDisplay)
        precondition(manager.remoteState.mode == .systemAndDisplay)
        let controls = MacControls(awakeState: { manager.remoteState }, setAwake: { try manager.applyRemotely($0) })
        let result = await controls.perform(MacControlRequest(action: .keepAwake(.off)))
        precondition(result.error == nil && manager.mode == .off)
        let state = await controls.snapshot()
        precondition(state.keepAwake?.sessionActive == true)
        let unavailable = await MacControls().perform(MacControlRequest(action: .keepAwake(.system)))
        precondition(unavailable.error != nil, "A host without an awake controller must reject the action")
        print("PASS: remote assertions, active-session protection, snapshots and local-only lid control")
    }
}
