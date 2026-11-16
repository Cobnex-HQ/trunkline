import AppKit
import ApplicationServices

/// Uses only this process's temporary windows. No user window is activated or changed.
@MainActor private final class WindowListCheckDelegate: NSObject, NSApplicationDelegate {
    private var owned: [NSWindow] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await run() }
        Task { try? await Task.sleep(for: .seconds(25)); finish(1, "FAIL: window-list check timed out") }
    }
    private func finish(_ code: Int32, _ message: String) -> Never {
        owned.forEach { $0.close() }; print(message); fflush(stdout); exit(code)
    }
    private func run() async {
        guard AXIsProcessTrusted() else { finish(77, "SKIP: Accessibility unavailable; no permission requested") }
        for number in 1...29 {
            let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 220, height: 140),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.title = "Trunkline list check \(number)"
            window.orderBack(nil); owned.append(window)
        }
        let controls = MacControls()
        let first = await controls.snapshot(windowAppPID: ProcessInfo.processInfo.processIdentifier)
        guard first.windows.count == 24 else { finish(1, "FAIL: expected a bounded first batch of 24 owned windows, got \(first.windows.count)") }
        let encoded = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(first)) as! [String: Any]
        guard let page = encoded["windowPage"] as? [String: Any], page["nextCursor"] is String else {
            finish(1, "FAIL: windows beyond the first 24 are silently unreachable")
        }
        guard let cursor = first.windowPage?.nextCursor, first.windowPage?.totalCount == 29 else {
            finish(1, "FAIL: first batch omitted the total or continuation")
        }
        let next = await controls.snapshot(windowAppPID: ProcessInfo.processInfo.processIdentifier, windowCursor: cursor)
        guard Set(next.windows.map(\.title)) == Set(owned.map(\.title)), next.windows.count == 29,
              next.windowPage?.nextCursor == nil else {
            finish(1, "FAIL: continuation did not reach all 29 unique windows")
        }
        let preserved = await controls.snapshot(windowAppPID: ProcessInfo.processInfo.processIdentifier, preserveWindows: true)
        guard preserved.windows == next.windows else { finish(1, "FAIL: automatic refresh collapsed the expanded list") }
        // Controls must still accept a window from the first page after loading the second.
        let oldWindow = first.windows[0]
        let minimized = await controls.perform(MacControlRequest(action: .window(oldWindow.id, .minimize)))
        guard minimized.error == nil else { finish(1, "FAIL: continuation invalidated earlier window handles") }
        let refreshed = await controls.snapshot(windowAppPID: ProcessInfo.processInfo.processIdentifier)
        guard refreshed.windows.count == 24, refreshed.windowPage?.nextCursor != nil else {
            finish(1, "FAIL: explicit refresh did not start a new bounded list")
        }
        let expired = await controls.snapshot(windowAppPID: ProcessInfo.processInfo.processIdentifier, windowCursor: cursor)
        guard expired.windowScope?.error != nil else { finish(1, "FAIL: expired continuation was silently accepted") }
        let stillCurrent = await controls.snapshot(windowAppPID: ProcessInfo.processInfo.processIdentifier, preserveWindows: true)
        guard stillCurrent.windows == refreshed.windows, stillCurrent.windowPage == refreshed.windowPage else {
            finish(1, "FAIL: expired cursor damaged the current list")
        }
        finish(0, "PASS: 29 actual AX windows reachable in bounded batches; polling retains the list, earlier handles work, refresh invalidates old cursors")
    }
}
@main struct HostWindowListCheck {
    @MainActor static func main() {
        let app = NSApplication.shared; let delegate = WindowListCheckDelegate()
        app.setActivationPolicy(.regular); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
