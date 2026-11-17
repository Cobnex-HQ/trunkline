import Foundation

public enum SystemControl: String, Codable, CaseIterable, Identifiable, Sendable {
    case spotlight, missionControl, appWindows, showDesktop, switchApp, screenshot
    case playPause, nextTrack, previousTrack, brightnessUp, brightnessDown, lock, sleep
    public var id: Self { self }
    public var title: String {
        switch self {
        case .spotlight: "Spotlight"; case .missionControl: "Mission Control"
        case .appWindows: "App windows"; case .showDesktop: "Show desktop"
        case .switchApp: "Switch app"; case .screenshot: "Screenshot"
        case .playPause: "Play / pause"; case .nextTrack: "Next track"; case .previousTrack: "Previous track"
        case .brightnessUp: "Brighter"; case .brightnessDown: "Dimmer"
        case .lock: "Lock Mac"; case .sleep: "Sleep Mac"
        }
    }
    public var symbol: String {
        switch self {
        case .spotlight: "magnifyingglass"; case .missionControl: "rectangle.3.group"
        case .appWindows: "macwindow.on.rectangle"; case .showDesktop: "desktopcomputer"
        case .switchApp: "rectangle.on.rectangle"; case .screenshot: "camera.viewfinder"
        case .playPause: "playpause.fill"; case .nextTrack: "forward.end.fill"; case .previousTrack: "backward.end.fill"
        case .brightnessUp: "sun.max"; case .brightnessDown: "sun.min"
        case .lock: "lock"; case .sleep: "moon"
        }
    }
}
public enum WindowControl: String, Codable, CaseIterable, Sendable {
    case focus, minimize, maximize, leftHalf, rightHalf, fullscreen
    public var title: String {
        switch self { case .focus: "Bring forward"; case .minimize: "Minimize"; case .maximize: "Fill screen"
        case .leftHalf: "Tile left"; case .rightHalf: "Tile right"; case .fullscreen: "Toggle full screen" }
    }
}
public enum MacControlAction: Codable, Equatable, Sendable {
    case system(SystemControl)
    case power(MacPowerAction)
    case keepAwake(AwakeMode)
    case volume(Double)
    case mute(Bool)
    case audioOutput(String)
    case launchApp(String)
    case activateApp(Int32)
    case quitApp(Int32)
    case window(UUID, WindowControl)
    case moveWindow(UUID, displayID: UInt32)
    case desktopDisplay(String)
    public var requiresConfirmation: Bool {
        switch self { case .power, .quitApp, .system(.lock), .system(.sleep): true; default: false }
    }
    public func validate() throws {
        switch self {
        case .keepAwake(.lidClosed): throw MacControlError.invalid
        case let .desktopDisplay(id):
            guard !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) }), let number = UInt32(id), number != 0 else { throw MacControlError.invalid }
        case let .moveWindow(_, displayID): guard displayID != 0 else { throw MacControlError.invalid }
        case let .volume(value): guard value.isFinite, (0...1).contains(value) else { throw MacControlError.invalid }
        case let .audioOutput(uid):
            guard (1...1024).contains(uid.utf8.count),
                  uid.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { throw MacControlError.invalid }
        case let .activateApp(pid), let .quitApp(pid): guard pid > 0 else { throw MacControlError.invalid }
        case let .launchApp(bundle):
            guard (3...255).contains(bundle.utf8.count), bundle.contains("."),
                  bundle.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46,95].contains($0) }) else { throw MacControlError.invalid }
        default: break
        }
    }
}
public struct MacControlRequest: Codable, Equatable, Sendable {
    public let id: UUID
    public let action: MacControlAction
    public init(id: UUID = UUID(), action: MacControlAction) { self.id = id; self.action = action }
}
public struct MacControlResult: Codable, Equatable, Sendable {
    public let id: UUID
    public let error: String?
    public init(id: UUID, error: String? = nil) { self.id = id; self.error = error }
}
public struct MacApplication: Codable, Equatable, Identifiable, Sendable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let name: String
    public let bundleID: String
    public let active: Bool
    public init(pid: Int32, name: String, bundleID: String, active: Bool) {
        self.pid = pid; self.name = name; self.bundleID = bundleID; self.active = active
    }
}
public struct MacWindow: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let minimized: Bool
    /// Nil denotes an older host. False means this window cannot currently move.
    public let canMoveToDisplay: Bool?
    public init(id: UUID, title: String, minimized: Bool, canMoveToDisplay: Bool? = nil) {
        self.id = id; self.title = title; self.minimized = minimized; self.canMoveToDisplay = canMoveToDisplay
    }
}
public struct MacDisplayInfo: Codable, Equatable, Identifiable, Sendable {
    public let id: UInt32
    public let name: String
    public let width: Int
    public let height: Int
    public init(id: UInt32, name: String, width: Int, height: Int) { self.id = id; self.name = name; self.width = width; self.height = height }
}
public struct MacWindowScope: Codable, Equatable, Sendable {
    /// Nil follows the frontmost app. A missing application with a requested PID means it closed.
    public let requestedPID: Int32?
    public let application: MacApplication?
    public let error: String?
    public init(requestedPID: Int32?, application: MacApplication?, error: String? = nil) {
        self.requestedPID = requestedPID; self.application = application; self.error = error
    }
}
/// Continuation belongs to the current app's captured window list. Nil metadata means an older host.
public struct MacWindowPage: Codable, Equatable, Sendable {
    public let nextCursor: UUID?
    public let totalCount: Int
    public init(nextCursor: UUID?, totalCount: Int) { self.nextCursor = nextCursor; self.totalCount = totalCount }
}
public struct MacControlSnapshot: Codable, Equatable, Sendable {
    public var apps: [MacApplication]
    public var windows: [MacWindow]
    public var displays: [MacDisplayInfo]
    public var volume: Double?
    public var muted: Bool?
    public var accessibility: Bool
    public var frontmostApp: String
    /// Nil denotes a host that does not yet publish its installed application catalog.
    public var installedApps: [MacInstalledApplication]?
    public var loadingApps: Bool?
    /// Nil means this host does not expose output selection. An empty array means no usable outputs.
    public var audioOutputs: [MacAudioOutput]?
    public var power: MacPowerCapability?
    public var keepAwake: MacAwakeState?
    public var windowScope: MacWindowScope?
    public var requestID: UUID?
    public var windowPage: MacWindowPage?
    /// Nil when the bundled desktop engine does not support monitor selection.
    public var desktopDisplays: DesktopDisplaySelection?
    public init(apps: [MacApplication], windows: [MacWindow], displays: [MacDisplayInfo], volume: Double?, muted: Bool?, accessibility: Bool, frontmostApp: String, installedApps: [MacInstalledApplication]? = nil, loadingApps: Bool? = nil, audioOutputs: [MacAudioOutput]? = nil, power: MacPowerCapability? = nil, windowScope: MacWindowScope? = nil, requestID: UUID? = nil, windowPage: MacWindowPage? = nil, desktopDisplays: DesktopDisplaySelection? = nil) {
        self.apps = apps; self.windows = windows; self.displays = displays; self.volume = volume; self.muted = muted
        self.accessibility = accessibility; self.frontmostApp = frontmostApp
        self.installedApps = installedApps
        self.loadingApps = loadingApps
        self.audioOutputs = audioOutputs
        self.power = power
        self.windowScope = windowScope; self.requestID = requestID; self.windowPage = windowPage; self.desktopDisplays = desktopDisplays
    }
}
public struct MacAudioOutput: Codable, Equatable, Identifiable, Sendable {
    /// Core Audio UID, stable across restarts; never a process-local AudioObjectID.
    public let id: String
    public let name: String
    public let selected: Bool
    public init(id: String, name: String, selected: Bool) {
        self.id = id; self.name = name; self.selected = selected
    }
}
public enum MacControlError: LocalizedError {
    case invalid, unavailable, accessibility, missingApp, missingWindow, missingAudioOutput, missingDisplay, fullscreenWindow
    public var errorDescription: String? {
        switch self {
        case .invalid: "Invalid control request."
        case .unavailable: "This control is unavailable on the Mac’s current device or app."
        case .accessibility: "Enable Accessibility for Trunkline in Mac Settings."
        case .missingApp: "This app has closed. Refresh the app list."
        case .missingWindow: "This window has changed. Refresh the window list."
        case .missingAudioOutput: "This audio output is no longer connected. Refresh the device list."
        case .missingDisplay: "This display is no longer connected. Refresh the display list."
        case .fullscreenWindow: "Leave full screen before moving this window to another display."
        }
    }
}
