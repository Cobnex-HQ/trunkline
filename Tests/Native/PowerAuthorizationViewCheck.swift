import AppKit
import SwiftUI
import Foundation

// Substitute only the OS permission query. This check never requests consent,
// changes privacy settings, or sends a power event to the real Mac.
private final class PermissionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var flags: [Bool] = []
    func read(_ allowPrompt: Bool) -> MacPowerCapability {
        lock.lock(); flags.append(allowPrompt); let count = flags.count; lock.unlock()
        return .init(actions: count > 1 ? MacPowerAction.allCases.map(\.rawValue) : [], authorizationRequired: count == 1)
    }
    var calls: [Bool] { lock.lock(); defer { lock.unlock() }; return flags }
}
private let probe = PermissionProbe()
struct HostPower {
    func capability(allowPrompt: Bool) -> MacPowerCapability { probe.read(allowPrompt) }
}

@main struct PowerAuthorizationViewCheck {
    @MainActor static func main() async {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 350),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: Form { PowerControlsAuthorizationView() }.formStyle(.grouped))
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        let initialDeadline = ContinuousClock.now + .seconds(3)
        while probe.calls.isEmpty && ContinuousClock.now < initialDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        guard !probe.calls.isEmpty else { print("FAIL: view did not perform its initial query"); exit(1) }
        let before = probe.calls.count
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: app)
        let refreshDeadline = ContinuousClock.now + .seconds(2)
        while probe.calls.count == before && ContinuousClock.now < refreshDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        guard probe.calls.count > before else { print("FAIL: returning from Settings did not refresh power authorization"); exit(1) }
        guard !probe.calls.contains(true) else { print("FAIL: automatic refresh requested permission"); exit(1) }
        print("PASS: production SwiftUI Power view refreshes on activation without requesting consent")
    }
}
