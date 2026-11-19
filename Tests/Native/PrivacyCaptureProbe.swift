import AppKit
import ScreenCaptureKit

// Standalone experiment, excluded from the shipping app. Captures only its own
// small test area, keeps images in memory and writes pass/fail metadata.
@MainActor
final class PrivacyProbe: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var label: NSTextField!
    private var patches: [NSWindow] = []
    private var finished = false
    private let resultURL = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("result.json")
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 180),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Trunkline Privacy Check"
        window.delegate = self
        window.isReleasedWhenClosed = false
        label = NSTextField(wrappingLabelWithString: "Checking capture permissions…")
        label.frame = NSRect(x: 24, y: 24, width: 492, height: 120)
        window.contentView?.addSubview(label)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            complete("permission-required", "Enable Screen Recording for Trunkline Privacy Check in System Settings, then quit and reopen this check. Your existing Trunkline permissions are unchanged.")
            return
        }
        label.stringValue = "Testing a small black curtain over a green test window. No screenshots are saved."
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, !self.finished else { return }
            self.complete("failed", "Capture timed out. Privacy mode remains unavailable.")
            NSApp.terminate(nil)
        }
        Task { await check() }
    }
    func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
    private func complete(_ status: String, _ message: String) {
        finished = true
        patches.forEach { $0.orderOut(nil) }
        patches.removeAll()
        label.stringValue = message
        if let data = try? JSONSerialization.data(withJSONObject: ["status": status, "message": message], options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: resultURL, options: .atomic)
        }
    }
    private func patch(_ rect: NSRect, color: NSColor) -> NSWindow {
        let patch = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        patch.isReleasedWhenClosed = false
        patch.backgroundColor = color
        patch.isOpaque = true
        patch.hasShadow = false
        patch.ignoresMouseEvents = true
        patch.level = .floating
        patch.orderFrontRegardless()
        patches.append(patch)
        return patch
    }
    private func check() async {
        do {
            let displayID = CGMainDisplayID()
            guard let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID }) else {
                complete("failed", "No active main screen."); return
            }
            let rect = NSRect(x: screen.frame.minX + 80, y: screen.frame.minY + 80, width: 320, height: 180)
            _ = patch(rect, color: NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
            let curtain = patch(rect, color: .black)
            try await Task.sleep(for: .milliseconds(350))
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }),
                  let excluded = content.windows.first(where: { $0.windowID == CGWindowID(curtain.windowNumber) }) else {
                complete("failed", "The test curtain could not be identified for exclusion."); return
            }
            let config = SCStreamConfiguration()
            config.width = 320; config.height = 180
            config.showsCursor = false
            config.sourceRect = CGRect(x: 80, y: screen.frame.height - 260, width: 320, height: 180)
            let covered = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: config)
            let filtered = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: [excluded]), configuration: config)
            let a = pixel(covered), b = pixel(filtered)
            guard a[0] < 20, a[1] < 20, a[2] < 20, b[0] < 40, b[1] > 180, b[2] < 40 else {
                complete("failed", "The covered and excluded test images did not match. Privacy mode remains unavailable."); return
            }
            complete("passed", "Capture exclusion passed: black locally, green in the filtered capture. This is a feasibility result, not a finished privacy mode. Live video, input, Spaces, monitors and recovery still need integration tests.")
        } catch {
            complete("failed", "Capture failed: \(error.localizedDescription)")
        }
    }
    private func pixel(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { buffer in
            if let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
        }
        return bytes
    }
}

@main
struct PrivacyCaptureProbeApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = PrivacyProbe()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
    }
}
