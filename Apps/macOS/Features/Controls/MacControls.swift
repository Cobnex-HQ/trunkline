#if canImport(TrunklineCore)
import TrunklineCore
#endif
import AppKit
import ApplicationServices
import CoreAudio
import IOKit
import IOKit.pwr_mgt

/// Accessibility requests run on this actor, never the UI/network main queue.
actor MacControls {
    private let power: HostPower
    private let awakeState: @MainActor @Sendable () -> MacAwakeState?
    private let setAwake: @MainActor @Sendable (AwakeMode) throws -> Void
    init(power: HostPower = HostPower(),
         awakeState: @escaping @MainActor @Sendable () -> MacAwakeState? = { nil },
         setAwake: @escaping @MainActor @Sendable (AwakeMode) throws -> Void = { _ in throw MacControlError.unavailable }) {
        self.power = power
        self.awakeState = awakeState
        self.setAwake = setAwake
    }
    private var windows: [UUID: AXUIElement] = [:]
    private struct WindowListing {
        let requestedPID: Int32?
        let application: MacApplication
        var remaining: [AXUIElement]
        var items: [MacWindow]
        var handles: [UUID: AXUIElement]
        var nextCursor: UUID?
        let totalCount: Int
        var error: String?
        var page: MacWindowPage { MacWindowPage(nextCursor: nextCursor, totalCount: totalCount) }
    }
    private var windowListing: WindowListing?
    private var recent: [UUID: MacControlResult] = [:]
    private var order: [UUID] = []
    private var installedApps: [MacInstalledApplication]?
    private var catalogUpdated = Date.distantPast
    private var catalogTask: Task<Void, Never>?

    func snapshot(windowAppPID: Int32? = nil, requestID: UUID? = nil, windowCursor: UUID? = nil, preserveWindows: Bool = false) async -> MacControlSnapshot {
        // Discovery cannot occupy the control actor: volume/window commands must
        // remain available while a slow disk or large app directory is scanned.
        if catalogTask == nil, Date().timeIntervalSince(catalogUpdated) > 300 {
            let discovery = Task.detached(priority: .utility) {
                ApplicationCatalog.discover(in: [
                    URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"),
                    URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
                    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
                ])
            }
            catalogTask = Task { [weak self] in
                let apps = await discovery.value
                await self?.didDiscoverApplications(apps)
            }
        }
        let state = await MainActor.run {
            let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }
            let apps = running.map { MacApplication(pid: $0.processIdentifier, name: $0.localizedName ?? "App", bundleID: $0.bundleIdentifier ?? "", active: $0.isActive) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let front = NSWorkspace.shared.frontmostApplication
            let displays = NSScreen.screens.map { screen in
                MacDisplayInfo(id: (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0,
                               name: screen.localizedName, width: Int(screen.frame.width), height: Int(screen.frame.height))
            }
            return (apps, front?.processIdentifier, front?.localizedName ?? "Mac", displays)
        }
        let trusted = AXIsProcessTrusted()
        let target = state.0.first { $0.pid == (windowAppPID ?? state.1) }
        var windowIssue: String? = windowAppPID != nil && target == nil ? "This app has closed. Choose another app." : nil
        var items: [MacWindow] = []
        var page: MacWindowPage?
        if trusted, let target {
            let saved = windowListing
            let sameApp = saved?.requestedPID == windowAppPID && saved?.application.pid == target.pid
            if let windowCursor, !sameApp || saved?.nextCursor != windowCursor {
                // An old cursor must not consume or replace a newer list.
                windowIssue = "The window list has changed. Refresh to load it again."
                if sameApp { items = saved?.items ?? [] }
            } else if preserveWindows, windowCursor == nil, sameApp, let saved {
                // Poll other controls without collapsing an expanded window list.
                items = saved.items; page = saved.page; windowIssue = saved.error
            } else {
                let listing = await readWindows(target: target, requestedPID: windowAppPID,
                                                continuing: windowCursor == nil ? nil : saved)
                windowListing = listing; windows = listing.handles
                items = listing.items; page = listing.page; windowIssue = listing.error
            }
        } else { windowListing = nil; windows = [:] }
        var snapshot = MacControlSnapshot(apps: state.0, windows: items, displays: state.3,
                                  volume: HostAudio.volume, muted: HostAudio.muted,
                                  accessibility: trusted, frontmostApp: state.2, installedApps: installedApps,
                                  loadingApps: installedApps == nil && catalogTask != nil,
                                  audioOutputs: HostAudio.outputs, power: power.capability(),
                                  windowScope: MacWindowScope(requestedPID: windowAppPID, application: target, error: windowIssue),
                                  requestID: requestID, windowPage: page)
        snapshot.keepAwake = await awakeState()
        return snapshot
    }

    private func readWindows(target: MacApplication, requestedPID: Int32?, continuing: WindowListing?) async -> WindowListing {
        let previous = windows
        return await Self.onAccessibilityThread(pid: target.pid) {
            var listing = continuing ?? WindowListing(requestedPID: requestedPID, application: target,
                remaining: [], items: [], handles: [:], nextCursor: nil, totalCount: 0)
            if continuing == nil {
                let application = AXUIElementCreateApplication(target.pid)
                AXUIElementSetMessagingTimeout(application, 0.25)
                var value: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
                guard result == .success, let elements = value as? [AXUIElement] else {
                    listing.error = "This app’s windows aren’t responding. Try refreshing."
                    return listing
                }
                listing = WindowListing(requestedPID: requestedPID, application: target, remaining: elements,
                    items: [], handles: [:], nextCursor: nil, totalCount: elements.count)
            }
            listing.error = nil
            let deadline = ContinuousClock.now.advanced(by: .seconds(1))
            var processed = 0
            for element in listing.remaining.prefix(24) {
                guard ContinuousClock.now < deadline else {
                    listing.error = "Some windows are slow to respond. Load more to continue."; break
                }
                AXUIElementSetMessagingTimeout(element, 0.1)
                let id = previous.first(where: { CFEqual($0.value, element) })?.key ?? UUID()
                listing.handles[id] = element
                var title: CFTypeRef?; var minimized: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
                AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &minimized)
                var movable = DarwinBoolean(false)
                let canMove = AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &movable) == .success && movable.boolValue
                let text = title as? String ?? ""
                listing.items.append(MacWindow(id: id, title: text.isEmpty ? "Untitled window" : String(text.prefix(240)),
                    minimized: minimized as? Bool ?? false, canMoveToDisplay: canMove))
                processed += 1
            }
            listing.remaining.removeFirst(processed)
            listing.nextCursor = listing.remaining.isEmpty ? nil : UUID()
            return listing
        }
    }

    private func didDiscoverApplications(_ apps: [MacInstalledApplication]) {
        installedApps = apps; catalogUpdated = Date(); catalogTask = nil
    }

    /// AX calls to our own process can enter AppKit directly instead of using IPC.
    /// Only those calls belong on MainActor; external apps retain bounded background I/O.
    private nonisolated static func onAccessibilityThread<Value>(pid: Int32, _ operation: @escaping () throws -> Value) async rethrows -> Value {
        if pid == ProcessInfo.processInfo.processIdentifier {
            return try await MainActor.run { try operation() }
        }
        return try operation()
    }
    private nonisolated static func withWindow<Value>(_ window: AXUIElement, _ operation: @escaping () throws -> Value) async throws -> Value {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { throw MacControlError.missingWindow }
        return try await onAccessibilityThread(pid: pid, operation)
    }

    func perform(_ request: MacControlRequest, selectDesktopDisplay: (@Sendable (String) async throws -> Void)? = nil, setDesktopBitrate: (@Sendable (UInt64, Int) async throws -> Void)? = nil) async -> MacControlResult {
        if let previous = recent[request.id] { return previous }
        let result: MacControlResult
        do {
            try Task.checkCancellation(); try request.action.validate()
            switch request.action {
            case let .desktopBitrate(session, kbps):
                guard let setDesktopBitrate else { throw MacControlError.unavailable }
                try await setDesktopBitrate(session, kbps)
            case let .desktopDisplay(id):
                guard let selectDesktopDisplay else { throw MacControlError.unavailable }
                try await selectDesktopDisplay(id)
            case let .power(action): try power.perform(action)
            case let .keepAwake(mode): try await setAwake(mode)
            case let .volume(value): try HostAudio.setVolume(value)
            case let .mute(value): try HostAudio.setMute(value)
            case let .audioOutput(uid): try HostAudio.selectOutput(uid)
            case let .activateApp(pid):
                let activated = await MainActor.run { NSRunningApplication(processIdentifier: pid)?.activate(options: .activateAllWindows) ?? false }
                guard activated else { throw MacControlError.missingApp }
            case let .quitApp(pid):
                guard pid != ProcessInfo.processInfo.processIdentifier else { throw MacControlError.unavailable }
                let accepted = await MainActor.run { NSRunningApplication(processIdentifier: pid)?.terminate() ?? false }
                guard accepted else { throw MacControlError.missingApp }
            case let .launchApp(bundle):
                let url = await MainActor.run { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) }
                guard let url else { throw MacControlError.missingApp }
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    Task { @MainActor in
                        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                        }
                    }
                }
            case let .window(id, operation): try await changeWindow(id, operation)
            case let .moveWindow(id, displayID): try await moveWindow(id, to: displayID)
            case let .system(action): try await system(action)
            }
            result = MacControlResult(id: request.id)
        } catch { result = MacControlResult(id: request.id, error: error.localizedDescription) }
        recent[request.id] = result; order.append(request.id)
        if order.count > 64 { recent.removeValue(forKey: order.removeFirst()) }
        return result
    }

    private func changeWindow(_ id: UUID, _ operation: WindowControl) async throws {
        guard AXIsProcessTrusted() else { throw MacControlError.accessibility }
        guard let window = windows[id] else { throw MacControlError.missingWindow }
        // Window actions can legitimately take longer than reading their labels.
        AXUIElementSetMessagingTimeout(window, 0.5)
        let status: AXError
        switch operation {
        case .focus:
            var pid: pid_t = 0; AXUIElementGetPid(window, &pid)
            let processID = pid
            _ = await MainActor.run { NSRunningApplication(processIdentifier: processID)?.activate(options: .activateAllWindows) }
            status = try await Self.withWindow(window) {
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                return AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            }
        case .minimize:
            status = try await Self.withWindow(window) { AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) }
        case .fullscreen:
            status = try await Self.withWindow(window) {
                var value: CFTypeRef?
                AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value)
                return AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, (value as? Bool == true) ? kCFBooleanFalse : kCFBooleanTrue)
            }
        case .maximize, .leftHalf, .rightHalf:
            let windowOrigin = try await Self.withWindow(window) {
                var position: CFTypeRef?; var point = CGPoint.zero
                AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position)
                if let position, CFGetTypeID(position) == AXValueGetTypeID() { AXValueGetValue(position as! AXValue, .cgPoint, &point) }
                return point
            }
            let frame = await MainActor.run { () -> CGRect in
                let top = NSScreen.screens.first?.frame.maxY ?? 0
                let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: windowOrigin.x + 20, y: top - windowOrigin.y - 20)) } ?? NSScreen.main
                guard let screen else { return .zero }
                let rect = screen.visibleFrame
                return CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
            }
            guard frame.width > 0 else { throw MacControlError.unavailable }
            status = try await Self.withWindow(window) {
                var size = frame.size; var origin = frame.origin
                if operation != .maximize { size.width /= 2 }
                if operation == .rightHalf { origin.x += size.width }
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                guard let position = AXValueCreate(.cgPoint, &origin), let dimensions = AXValueCreate(.cgSize, &size) else { throw MacControlError.unavailable }
                let move = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
                let resized = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
                guard move == .success else { throw MacControlError.unavailable }
                return resized
            }
        }
        guard status == .success else { throw MacControlError.unavailable }
    }

    private func moveWindow(_ id: UUID, to displayID: UInt32) async throws {
        guard AXIsProcessTrusted() else { throw MacControlError.accessibility }
        guard let window = windows[id] else { throw MacControlError.missingWindow }
        let original = try await Self.withWindow(window) {
            AXUIElementSetMessagingTimeout(window, 0.5)
            var fullscreen: CFTypeRef?
            AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullscreen)
            guard fullscreen as? Bool != true else { throw MacControlError.fullscreenWindow }
            var position: CFTypeRef?, dimensions: CFTypeRef?
            var origin = CGPoint.zero, size = CGSize.zero
            guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
                  AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &dimensions) == .success,
                  let position, CFGetTypeID(position) == AXValueGetTypeID(),
                  let dimensions, CFGetTypeID(dimensions) == AXValueGetTypeID(),
                  AXValueGetValue(position as! AXValue, .cgPoint, &origin),
                  AXValueGetValue(dimensions as! AXValue, .cgSize, &size) else { throw MacControlError.unavailable }
            return CGRect(origin: origin, size: size)
        }
        let areas = try await MainActor.run { () throws -> (CGRect, CGRect) in
            let screens = NSScreen.screens
            guard let primary = screens.first,
                  let destination = screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID }) else { throw MacControlError.missingDisplay }
            func axRect(_ rect: CGRect) -> CGRect {
                CGRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
            }
            // Choose the display containing most of the window, including layouts
            // above/left of the primary. A fully offscreen window uses the primary.
            let source = screens.max { lhs, rhs in
                let a = original.intersection(axRect(lhs.frame)), b = original.intersection(axRect(rhs.frame))
                return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
            } ?? primary
            let intersects = !original.intersection(axRect(source.frame)).isNull
            return (axRect((intersects ? source : primary).visibleFrame), axRect(destination.visibleFrame))
        }
        let target = try WindowPlacement.move(window: original, from: areas.0, to: areas.1)
        try await Self.withWindow(window) {
            var movable = DarwinBoolean(false), resizable = DarwinBoolean(false)
            guard AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &movable) == .success,
                  movable.boolValue else { throw MacControlError.unavailable }
            if target.size != original.size {
                guard AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &resizable) == .success,
                      resizable.boolValue else { throw MacControlError.unavailable }
                var targetSize = target.size
                guard let value = AXValueCreate(.cgSize, &targetSize),
                      AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) == .success else { throw MacControlError.unavailable }
            }
            var targetOrigin = target.origin
            guard let value = AXValueCreate(.cgPoint, &targetOrigin),
                  AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success else { throw MacControlError.unavailable }
        }
    }

    private func system(_ action: SystemControl) async throws {
        if action == .sleep {
            let connection = IOPMFindPowerManagement(mach_task_self_)
            guard connection != 0 else { throw MacControlError.unavailable }
            defer { IOServiceClose(connection) }
            guard IOPMSleepSystem(connection) == kIOReturnSuccess else { throw MacControlError.unavailable }
            return
        }
        guard AXIsProcessTrusted() else { throw MacControlError.accessibility }
        switch action {
        case .spotlight: try key(49, .maskCommand)
        case .missionControl: try key(126, .maskControl)
        case .appWindows: try key(125, .maskControl)
        case .showDesktop: try key(103, [])
        case .switchApp: try key(48, .maskCommand)
        case .screenshot: try key(20, [.maskCommand, .maskShift])
        case .lock: try key(12, [.maskCommand, .maskControl])
        case .playPause: try mediaKey(16)
        case .nextTrack: try mediaKey(17)
        case .previousTrack: try mediaKey(18)
        case .brightnessUp: try mediaKey(2)
        case .brightnessDown: try mediaKey(3)
        case .sleep: break
        }
    }
    private func key(_ code: CGKeyCode, _ flags: CGEventFlags) throws {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { throw MacControlError.unavailable }
        down.flags = flags; up.flags = flags; down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    }
    private func mediaKey(_ code: Int) throws {
        for state in [0xA, 0xB] {
            guard let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                                               timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                               data1: (code << 16) | (state << 8), data2: -1)?.cgEvent else { throw MacControlError.unavailable }
            event.post(tap: .cghidEventTap)
        }
    }
}

private enum HostAudio {
    private static var availableOutputs: [(device: AudioDeviceID, uid: String, name: String)] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr,
              size > 0, size <= 65_536 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let status = ids.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!)
        }
        guard status == noErr else { return [] }
        return ids.prefix(Int(size) / MemoryLayout<AudioDeviceID>.size).compactMap { id in
            guard scalar(id, kAudioDevicePropertyDeviceIsAlive) == 1,
                  scalar(id, kAudioDevicePropertyDeviceCanBeDefaultDevice, scope: kAudioDevicePropertyScopeOutput) == 1,
                  let uid = string(id, kAudioDevicePropertyDeviceUID),
                  (try? MacControlAction.audioOutput(uid).validate()) != nil else { return nil }
            return (id, uid, String((string(id, kAudioObjectPropertyName) ?? "Audio output").prefix(160)))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    static var outputs: [MacAudioOutput] {
        let selected = device
        return availableOutputs.map { MacAudioOutput(id: $0.uid, name: $0.name, selected: $0.device == selected) }
    }
    static func selectOutput(_ uid: String) throws {
        // Resolve the UID against currently connected, output-capable devices.
        // A disconnected/replaced device must never turn a stale numeric ID into another target.
        guard let output = availableOutputs.first(where: { $0.uid == uid }) else { throw MacControlError.missingAudioOutput }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = output.device
        guard AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &id) == noErr else { throw MacControlError.unavailable }
    }
    private static func scalar(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout.size(ofValue: value))
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
    static var device: AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: AudioDeviceID = 0; var size = UInt32(MemoryLayout.size(ofValue: value))
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &value) == noErr && value != 0 ? value : nil
    }
    static func volumeElements(_ device: AudioDeviceID) -> [UInt32] {
        [UInt32(0),1,2].filter { element in
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            return AudioObjectHasProperty(device, &address)
        }.reduce(into: []) { values, element in if element == 0 || !values.contains(0) { values.append(element) } }
    }
    static var volume: Double? {
        guard let device else { return nil }
        let values: [Float32] = volumeElements(device).compactMap { element in
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            var value: Float32 = 0; var size = UInt32(MemoryLayout<Float32>.size)
            return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
        }
        return values.isEmpty ? nil : Double(values.reduce(0,+) / Float(values.count))
    }
    static var muted: Bool? {
        guard let device else { return nil }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value != 0 : nil
    }
    static func setVolume(_ value: Double) throws {
        guard let device else { throw MacControlError.unavailable }
        let elements = volumeElements(device); guard !elements.isEmpty else { throw MacControlError.unavailable }
        for element in elements {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            var scalar = Float32(value)
            guard AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &scalar) == noErr else { throw MacControlError.unavailable }
        }
    }
    static func setMute(_ value: Bool) throws {
        guard let device else { throw MacControlError.unavailable }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var muted: UInt32 = value ? 1 : 0
        guard AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &muted) == noErr else { throw MacControlError.unavailable }
    }
}
