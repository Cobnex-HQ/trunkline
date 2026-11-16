import AppKit
import ApplicationServices

/// Exercises production Accessibility routing against this process's own temporary
/// window only. Never activates or moves the user's windows, and never asks for consent.
@MainActor
private final class WindowMoveCheckDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await run() }
        Task {
            try? await Task.sleep(for: .seconds(20))
            print("FAIL: owned-window control check timed out"); exit(1)
        }
    }
    private func finish(_ code: Int32, _ message: String) -> Never {
        window?.close(); print(message); fflush(stdout); exit(code)
    }
    private func run() async {
        guard AXIsProcessTrusted() else { finish(77, "SKIP: Accessibility is unavailable; no permission was requested") }
        guard let screen = NSScreen.screens.first,
              let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else {
            finish(77, "SKIP: no display is available")
        }
        let area = screen.visibleFrame
        let owned = NSWindow(contentRect: NSRect(x: area.maxX - 80, y: area.minY + 80, width: 420, height: 280),
                             styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        owned.isReleasedWhenClosed = false
        owned.title = "Trunkline window-control regression"
        owned.orderBack(nil)
        owned.setFrameOrigin(NSPoint(x: area.maxX - 80, y: area.minY + 80))
        window = owned
        let before = owned.frame
        guard before.maxX > area.maxX else { finish(1, "FAIL: test window was not positioned outside the usable area") }
        let controls = MacControls()
        var selected: MacWindow?
        for _ in 0..<20 {
            let state = await controls.snapshot(windowAppPID: ProcessInfo.processInfo.processIdentifier)
            selected = state.windows.first { $0.title == owned.title }
            if selected != nil { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let selected, selected.canMoveToDisplay == true else { finish(1, "FAIL: owned movable window was not advertised") }
        let invalid = await controls.perform(MacControlRequest(action: .moveWindow(selected.id, displayID: UInt32.max)))
        guard invalid.error != nil, owned.frame == before else { finish(1, "FAIL: disconnected display changed the test window") }
        let request = MacControlRequest(action: .moveWindow(selected.id, displayID: displayID))
        let result = await controls.perform(request)
        guard result.error == nil else { finish(1, "FAIL: owned window move: " + result.error!) }
        // AppKit applies AX changes on its run loop; wait for that observed change.
        for _ in 0..<100 {
            if abs(owned.frame.maxX - area.maxX) < 2 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        let after = owned.frame
        guard after != before, area.insetBy(dx: -2, dy: -2).contains(after), after.size == before.size else {
            finish(1, "FAIL: moved window was not contained or changed size unexpectedly: \(before) -> \(after), area \(area)")
        }
        // Duplicate IDs must return the recorded result rather than executing twice.
        owned.setFrameOrigin(before.origin)
        let duplicate = await controls.perform(request)
        guard duplicate == result, owned.frame.origin == before.origin else { finish(1, "FAIL: duplicate move executed twice") }
        let tiled = await controls.perform(MacControlRequest(action: .window(selected.id, .rightHalf)))
        guard tiled.error == nil else { finish(1, "FAIL: owned window tiling: " + tiled.error!) }
        for _ in 0..<100 {
            if abs(owned.frame.width - area.width / 2) < 2 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        guard abs(owned.frame.minX - area.midX) < 2, abs(owned.frame.width - area.width / 2) < 2 else {
            finish(1, "FAIL: existing tiling control did not place the owned window in the right half")
        }
        finish(0, "PASS: actual AX move/tiling of an owned window, destination rejection, usable bounds, retained size and duplicate suppression")
    }
}

@main struct HostWindowMoveCheck {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = WindowMoveCheckDelegate()
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
