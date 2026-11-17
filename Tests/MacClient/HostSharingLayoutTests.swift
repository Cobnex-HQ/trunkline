import XCTest
import SwiftUI
import AppKit
import ScreenCaptureKit
@testable import TrunklineHost

@MainActor
final class HostSharingLayoutTests: XCTestCase {
    func testSharingLayoutsInBothAppearances() async throws {
        let output = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("trunkline-host-layout")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let defaults = UserDefaults.standard
        let savedArguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defaults.setVolatileDomain(["away-access-enabled": false], forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(savedArguments, forName: UserDefaults.argumentDomain) }
        let model = HostModel()
        model.hasPasscode = true
        model.isRunning = true
        model.address = "example-mac.local"
        model.fingerprint = String(repeating: "a", count: 64)
        let client = MacClientModel()
        client.pairingText = ""
        for (name, appearance, width) in [("light", NSAppearance.Name.aqua, 940.0), ("dark", .darkAqua, 780.0)] {
            defaults.setVolatileDomain(["away-access-enabled": false, "trunkline.appearance": name], forName: UserDefaults.argumentDomain)
            for panel in HostView.Panel.allCases {
                let view = NSHostingView(rootView: HostView(model: model, client: client, initialPanel: panel).tint(Color("AccentColor")).environment(\.colorScheme, name == "dark" ? .dark : .light))
                view.appearance = NSAppearance(named: appearance)
                let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: width, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: appearance)
                window.title = "Trunkline · \(panel.rawValue)"
                window.contentView = view
                window.orderBack(nil)
                defer { window.close() }
                try await Task.sleep(for: .milliseconds(350))
                view.layoutSubtreeIfNeeded()
                let bitmap: NSBitmapImageRep
                if CGPreflightScreenCaptureAccess() {
                    do {
                        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                        let target = try XCTUnwrap(content.windows.first { $0.windowID == CGWindowID(window.windowNumber) })
                        let config = SCStreamConfiguration()
                        config.width = Int(window.frame.width * 2)
                        config.height = Int(window.frame.height * 2)
                        config.showsCursor = false
                        let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: target), configuration: config)
                        bitmap = NSBitmapImageRep(cgImage: image)
                    } catch {
                        // Permission can remain granted while capture is unavailable,
                        // for example while the Mac is locked. Do not call it app failure.
                        throw XCTSkip("Native window capture unavailable: \(error.localizedDescription)")
                    }
                } else {
                    bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                }
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: output.appendingPathComponent("mac-\(panel.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))-\(name).png"))
                XCTAssertGreaterThan(data.count, 1000)
            }
        }
        print("Layout snapshots: \(output.path)")
    }
}
