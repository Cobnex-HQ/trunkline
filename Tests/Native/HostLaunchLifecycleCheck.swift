import AppKit

// Substitute only the host's external work. The real NSApplication delegate
// must own startup independently of window creation; no network or TCC calls run.
@MainActor final class HostModel {
    var starts = 0
    var interactiveRequests = 0
    let terminals = InertTerminals()
    let keepAwake = InertAwake()
    let sunshine = InertDesktop()
    func startOnLaunchIfReady() async { starts += 1 }
    func requestPermissionsAndStartOnLaunchIfReady() async { interactiveRequests += 1; starts += 1 }
    func stop() {}
}
@MainActor final class InertTerminals {
    var runningCount = 0
    func closeAll() {}
}
@MainActor final class InertAwake { func prepareToQuit() -> Bool { true } }
@MainActor final class InertDesktop { func shutdown() async {} }

@main struct HostLaunchLifecycleCheck {
    @MainActor static func main() async {
        let delegate = HostAppDelegate()
        let owned: HostModel? = delegate.model
        guard let model = owned else { print("FAIL: No host model exists before a window appears"); exit(1) }
        let applicationDelegate: any NSApplicationDelegate = delegate
        applicationDelegate.applicationDidFinishLaunching?(Notification(name: NSApplication.didFinishLaunchingNotification))
        applicationDelegate.applicationDidFinishLaunching?(Notification(name: NSApplication.didFinishLaunchingNotification))
        for _ in 0..<20 { await Task.yield() }
        guard model.starts == 1 else { print("FAIL: App launch must start access exactly once without a window"); exit(2) }
        guard model.interactiveRequests == 0 else { print("FAIL: Automatic startup requested interactive permissions"); exit(3) }
        print("PASS: model owned before windows, one launch startup and no interactive permission requests")
    }
}
