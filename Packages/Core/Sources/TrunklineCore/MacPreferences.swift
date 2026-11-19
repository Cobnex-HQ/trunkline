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
    public init() {}
}

public struct MacPreferencesStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load(_ id: String) -> MacPreferences {
        guard let data = defaults.data(forKey: "mac.preferences.\(id)") else { return MacPreferences() }
        return (try? JSONDecoder().decode(MacPreferences.self, from: data)) ?? MacPreferences()
    }
    public func save(_ preferences: MacPreferences, for id: String) {
        guard !id.isEmpty, let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: "mac.preferences.\(id)")
    }
    public func remove(_ id: String) { defaults.removeObject(forKey: "mac.preferences.\(id)") }
}
