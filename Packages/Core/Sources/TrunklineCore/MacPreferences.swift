import Foundation

public enum ClipboardSyncMode: String, Codable, CaseIterable, Sendable {
    case off, fromMac, bothDirections
    public var title: String {
        switch self {
        case .off: "Off"
        case .fromMac: "Mac to this device"
        case .bothDirections: "Both directions"
        }
    }
}

public struct MacPreferences: Codable, Equatable, Sendable {
    public var clipboard: ClipboardSyncMode = .off
    public var profile: StreamProfile = .responsive
    public var inputMode: DesktopInputMode = .directTouch
    public var pacing: StreamPacingMode = .lowLatency
    public var adaptiveQuality = true
    public var statistics = false
    public var displayID: String?
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case clipboard, profile, inputMode, pacing, adaptiveQuality, statistics, displayID
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        clipboard = (try? values.decode(ClipboardSyncMode.self, forKey: .clipboard)) ?? .off
        profile = (try? values.decode(StreamProfile.self, forKey: .profile)) ?? .responsive
        inputMode = (try? values.decode(DesktopInputMode.self, forKey: .inputMode)) ?? .directTouch
        pacing = (try? values.decode(StreamPacingMode.self, forKey: .pacing)) ?? .lowLatency
        adaptiveQuality = (try? values.decode(Bool.self, forKey: .adaptiveQuality)) ?? true
        statistics = (try? values.decode(Bool.self, forKey: .statistics)) ?? false
        displayID = try? values.decode(String.self, forKey: .displayID)
    }
    public func availableDisplay(in displays: [DesktopCaptureDisplay]) -> DesktopCaptureDisplay? {
        guard let displayID else { return nil }
        return displays.first { ($0.persistentID ?? $0.id) == displayID }
    }
}

public struct MacPreferencesStore {
    private static let updateLock = NSLock()
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func contains(_ id: String) -> Bool { defaults.data(forKey: "mac.preferences.\(id)") != nil }
    public func load(_ id: String) -> MacPreferences {
        guard let data = defaults.data(forKey: "mac.preferences.\(id)") else { return MacPreferences() }
        return (try? JSONDecoder().decode(MacPreferences.self, from: data)) ?? MacPreferences()
    }
    public func save(_ preferences: MacPreferences, for id: String) {
        guard !id.isEmpty, let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: "mac.preferences.\(id)")
    }
    public func update(_ id: String, _ change: (inout MacPreferences) -> Void) {
        Self.updateLock.lock()
        defer { Self.updateLock.unlock() }
        var preferences = load(id)
        change(&preferences)
        save(preferences, for: id)
    }
    public func remove(_ id: String) { defaults.removeObject(forKey: "mac.preferences.\(id)") }
}
