import AppKit
import AVFoundation
import TrunklineCore

/// AppKit owns focus, physical keyboard events, scrolling and window resizing.
final class MacDesktopView: NSView {
    let engine: MacDesktopEngine
    let aspect: CGFloat
    private var tracking: NSTrackingArea?
    private var heldKeys = Set<UInt16>()
    private var heldButtons = Set<Int32>()
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(engine: MacDesktopEngine, aspect: CGFloat) {
        self.engine = engine
        self.aspect = aspect
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(engine.displayLayer)
        setAccessibilityLabel("Remote Mac desktop")
        setAccessibilityHelp("Click to control. Press Control Option Escape to release keyboard control.")
    }
    required init?(coder: NSCoder) { fatalError("Use init(engine:aspect:)") }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        engine.displayLayer.frame = bounds
        CATransaction.commit()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        tracking = area
        addTrackingArea(area)
    }
    private func position(_ event: NSEvent, clamp: Bool = false) -> Bool {
        var point = convert(event.locationInWindow, from: nil)
        if clamp {
            let rect = ViewportGeometry.videoRect(in: bounds.size, aspect: aspect)
            point.x = min(max(point.x, rect.minX), rect.maxX - 0.001)
            point.y = min(max(point.y, rect.minY), rect.maxY - 0.001)
        }
        guard let point = MacDesktopInput.position(point, size: bounds.size, aspect: aspect) else { return false }
        engine.moveX(Double(point.x), y: Double(point.y))
        return true
    }
    override func mouseMoved(with event: NSEvent) { _ = position(event) }
    override func mouseDragged(with event: NSEvent) { _ = position(event, clamp: true) }
    override func rightMouseDragged(with event: NSEvent) { _ = position(event, clamp: true) }
    override func otherMouseDragged(with event: NSEvent) { _ = position(event, clamp: true) }
    private func button(_ event: NSEvent, number: Int32, down: Bool) {
        if down {
            guard position(event) else { return }
            window?.makeFirstResponder(self)
            heldButtons.insert(number)
        } else {
            guard heldButtons.remove(number) != nil else { return }
            _ = position(event, clamp: true)
        }
        engine.button(number, down: down)
    }
    override func mouseDown(with event: NSEvent) { button(event, number: 1, down: true) }
    override func mouseUp(with event: NSEvent) { button(event, number: 1, down: false) }
    override func rightMouseDown(with event: NSEvent) { button(event, number: 3, down: true) }
    override func rightMouseUp(with event: NSEvent) { button(event, number: 3, down: false) }
    override func otherMouseDown(with event: NSEvent) { button(event, number: 2, down: true) }
    override func otherMouseUp(with event: NSEvent) { button(event, number: 2, down: false) }
    override func scrollWheel(with event: NSEvent) {
        guard position(event) else { return }
        let scale = event.hasPreciseScrollingDeltas ? 3.0 : 120.0
        engine.scrollX(Int16(clamping: Int(event.scrollingDeltaX * scale)), y: Int16(clamping: Int(event.scrollingDeltaY * scale)))
    }
    private func modifiers(_ event: NSEvent) -> UInt8 {
        var bits: UInt8 = 0
        if event.modifierFlags.contains(.shift) { bits |= 1 }
        if event.modifierFlags.contains(.control) { bits |= 2 }
        if event.modifierFlags.contains(.option) { bits |= 4 }
        if event.modifierFlags.contains(.command) { bits |= 8 }
        return bits
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 && event.modifierFlags.contains([.control, .option]) {
            releaseInput()
            window?.makeFirstResponder(nil)
            return
        }
        guard let key = MacDesktopInput.virtualKey(event.keyCode) else { return }
        heldKeys.insert(key)
        engine.key(key, down: true, modifiers: modifiers(event))
    }
    override func keyUp(with event: NSEvent) {
        guard let key = MacDesktopInput.virtualKey(event.keyCode) else { return }
        heldKeys.remove(key)
        engine.key(key, down: false, modifiers: modifiers(event))
    }
    override func flagsChanged(with event: NSEvent) {
        guard let key = MacDesktopInput.virtualKey(event.keyCode) else { return }
        if event.keyCode == 57 {
            engine.key(key, down: true, modifiers: modifiers(event))
            engine.key(key, down: false, modifiers: modifiers(event))
            return
        }
        let down = !heldKeys.contains(key)
        if down { heldKeys.insert(key) } else { heldKeys.remove(key) }
        engine.key(key, down: down, modifiers: modifiers(event))
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.isKeyWindow == true, window?.firstResponder === self else { return false }
        keyDown(with: event)
        return true
    }
    func releaseInput() {
        for key in heldKeys { engine.key(key, down: false, modifiers: 0) }
        for button in heldButtons { engine.button(button, down: false) }
        heldKeys.removeAll()
        heldButtons.removeAll()
    }
    override func resignFirstResponder() -> Bool { releaseInput(); return super.resignFirstResponder() }
}

@MainActor
final class MacDesktopWindow: NSWindowController, NSWindowDelegate {
    private let desktop: MacDesktopView
    var onClose: (() -> Void)?
    init(engine: MacDesktopEngine, name: String, size: DesktopStreamGeometry.Size) {
        desktop = MacDesktopView(engine: engine, aspect: CGFloat(size.width) / CGFloat(size.height))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = name
        window.subtitle = "Control–Option–Escape releases keyboard control"
        window.contentView = desktop
        window.minSize = NSSize(width: 480, height: 320)
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        super.init(window: window)
        window.delegate = self
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("Use init(engine:name:size:)") }
    func open() { showWindow(nil); window?.makeKeyAndOrderFront(nil); window?.makeFirstResponder(desktop) }
    func windowDidResignKey(_ notification: Notification) { desktop.releaseInput() }
    func windowWillClose(_ notification: Notification) { desktop.releaseInput(); onClose?() }
}
