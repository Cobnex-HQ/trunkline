import Foundation

/// A capture identity is valid for the current Mac display topology, not a list position.
public struct DesktopCaptureDisplay: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let persistentID: String?
    public let name: String
    public let width: Int
    public let height: Int
    public init(id: String, name: String, width: Int, height: Int, persistentID: String? = nil) {
        self.persistentID = persistentID
        self.id = id; self.name = name; self.width = width; self.height = height
    }
    public var geometry: DesktopDisplay { DesktopDisplay(width: width, height: height) }
}

/// Shared engine/companion contract. A preferred display is not proof that capture switched.
public struct DesktopDisplaySelection: Codable, Equatable, Sendable {
    public let status: Bool
    public let supported: Bool
    public let displays: [DesktopCaptureDisplay]
    public let activeID: String?
    public let preferredID: String?
    public let switching: Bool
    public let error: String?
    enum CodingKeys: String, CodingKey {
        case status, supported, displays, switching, error
        case activeID = "active_id", preferredID = "preferred_id"
    }
    public init(displays: [DesktopCaptureDisplay], activeID: String? = nil, preferredID: String? = nil,
                switching: Bool = false, error: String? = nil, status: Bool = true, supported: Bool = true) {
        self.displays = displays; self.activeID = activeID; self.preferredID = preferredID
        self.switching = switching; self.error = error; self.status = status; self.supported = supported
    }
    public var isAvailable: Bool { status && supported }
    public var selectedDisplay: DesktopCaptureDisplay? {
        displays.first { $0.id == (preferredID ?? activeID) }
    }
    /// Add native display names without changing capture identities, order or state.
    public func withDisplayNames(_ names: [String: String], identities: [String: String] = [:]) -> Self {
        let named = displays.map { display in
            let name = names[display.id]?.trimmingCharacters(in: .whitespacesAndNewlines)
            return DesktopCaptureDisplay(id: display.id,
                name: name.flatMap { $0.isEmpty ? nil : $0 } ?? display.name,
                width: display.width, height: display.height, persistentID: identities[display.id] ?? display.persistentID)
        }
        return Self(displays: named, activeID: activeID, preferredID: preferredID,
                    switching: switching, error: error, status: status, supported: supported)
    }
}
