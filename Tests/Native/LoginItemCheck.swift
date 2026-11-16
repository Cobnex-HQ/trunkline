import AppKit
import ServiceManagement

/// The real manager handles state; only OS registration is substituted so this
/// regression never changes the user's login items or opens System Settings.
@main struct LoginItemCheck {
    @MainActor static func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
    @MainActor static func main() async {
        var status: SMAppService.Status = .notRegistered
        var registrations = 0
        var removals = 0
        var refuse = false
        let center = NotificationCenter()
        let manager = KeepAwakeManager(loginStatus: { status }, registerLogin: {
            registrations += 1
            if refuse { throw NSError(domain: "LoginItemCheck", code: 1) }
            status = .requiresApproval
        }, unregisterLogin: {
            removals += 1
            if refuse { throw NSError(domain: "LoginItemCheck", code: 2) }
            status = .notRegistered
        }, notificationCenter: center)
        precondition(!manager.startsAtLogin && !manager.loginRequested)
        manager.setStartsAtLogin(true)
        precondition(manager.loginStatus == .requiresApproval && !manager.startsAtLogin,
                     "Registration awaiting consent must never appear ready")
        precondition(manager.loginRequested, "Pending registration must remain cancellable")
        manager.setStartsAtLogin(true)
        precondition(registrations == 1, "Pending approval must not repeatedly register")
        status = .enabled
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await waitUntil { manager.startsAtLogin }
        precondition(manager.startsAtLogin, "Returning from Settings must refresh approval")
        status = .requiresApproval
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await waitUntil { !manager.startsAtLogin }
        precondition(!manager.startsAtLogin, "Revoked approval must not remain ready")
        manager.setStartsAtLogin(false)
        precondition(removals == 1 && !manager.loginRequested)
        refuse = true
        manager.setStartsAtLogin(true)
        precondition(manager.error != nil && !manager.startsAtLogin,
                     "Failed registration must preserve actual OS state")
        refuse = false
        manager.setStartsAtLogin(true)
        precondition(manager.error == nil && manager.loginRequested,
                     "A successful retry must clear the previous operation error")
        refuse = true
        manager.setStartsAtLogin(false)
        precondition(manager.error != nil && manager.loginRequested,
                     "Failed cancellation must not falsely turn off registration")
        status = .notFound
        manager.refreshLoginStatus()
        precondition(!manager.startsAtLogin && !manager.loginRequested)
        print("PASS: pending approval, activation refresh, revocation, cancellation, failure and retry; no login items modified")
    }
}
