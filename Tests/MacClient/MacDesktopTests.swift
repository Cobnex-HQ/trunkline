import XCTest
import AppKit
import TrunklineCore
@testable import TrunklineHost

@MainActor
final class MacDesktopTests: XCTestCase {
    func testConnectionHealthControlHasAVisibleSize() throws {
        let controller = MacDesktopWindow(engine: RecordingMacEngine(), name: "Fixture", size: .init(width: 1280, height: 720))
        controller.configureHealth {
            ConnectionHealth(now: 10, roundTripMS: 25, roundTripTime: 10, frameLoss: 0.01, videoTime: 10, videoKbps: 12000, route: .away)
        }
        defer { controller.close() }
        let button = try XCTUnwrap(controller.window?.titlebarAccessoryViewControllers.first?.view as? NSButton)
        XCTAssertGreaterThan(button.frame.width, 40)
        XCTAssertGreaterThan(button.frame.height, 15)
        XCTAssertEqual(button.title, "Connection health")
    }

    func testMouseMapsToVideoAndReleasesOutsideThePicture() throws {
        let engine = RecordingMacEngine()
        let view = MacDesktopView(engine: engine, aspect: 2)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let local = CGPoint(x: 250, y: 275)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: view.convert(local, to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        view.mouseDown(with: event)
        XCTAssertEqual(engine.position?.x ?? -1, 0.25, accuracy: 0.001)
        XCTAssertEqual(engine.position?.y ?? -1, 0.25, accuracy: 0.001)
        XCTAssertEqual(engine.buttons.last?.0, 1)
        XCTAssertEqual(engine.buttons.last?.1, true)
        let outside = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: CGPoint(x: -100, y: -100), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
        view.mouseUp(with: outside)
        XCTAssertEqual(engine.buttons.last?.1, false)
    }
    func testLosingFocusReleasesHeldKeysAndButtons() throws {
        let engine = RecordingMacEngine()
        let view = MacDesktopView(engine: engine, aspect: 1)
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0))
        view.keyDown(with: event)
        XCTAssertEqual(engine.keys.last?.0, 0x41)
        XCTAssertEqual(engine.keys.last?.1, true)
        view.releaseInput()
        XCTAssertEqual(engine.keys.last?.1, false)
        let count = engine.keys.count
        view.releaseInput()
        XCTAssertEqual(engine.keys.count, count)
    }
}

private final class RecordingMacEngine: MacDesktopEngine {
    var position: CGPoint?
    var buttons: [(Int32, Bool)] = []
    var keys: [(UInt16, Bool)] = []
    override func moveX(_ x: Double, y: Double) { position = CGPoint(x: x, y: y) }
    override func button(_ button: Int32, down: Bool) { buttons.append((button, down)) }
    override func key(_ key: UInt16, down: Bool, modifiers: UInt8) { keys.append((key, down)) }
}
