import Foundation

public enum MacPowerAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case restart, shutDown, logOut
    public var id: Self { self }
    public var title: String {
        switch self { case .restart: "Restart Mac"; case .shutDown: "Shut Down Mac"; case .logOut: "Log Out of Mac" }
    }
    public var symbol: String {
        switch self { case .restart: "restart"; case .shutDown: "power"; case .logOut: "rectangle.portrait.and.arrow.right" }
    }
    public var consequence: String {
        switch self {
        case .restart: "Save your work first. This ends the connection and terminal sessions. Reconnect after the Mac has restarted, been unlocked and logged in."
        case .shutDown: "Save your work first. This ends the connection and terminal sessions. You’ll need to turn the Mac on again before reconnecting."
        case .logOut: "Save your work first. This ends the connection and terminal sessions. Log in to the Mac again before reconnecting."
        }
    }
}

public struct MacPowerCapability: Codable, Equatable, Sendable {
    /// Strings permit future hosts to advertise actions an older client can ignore.
    public let actions: [String]
    public let authorizationRequired: Bool
    public var availableActions: [MacPowerAction] { actions.compactMap(MacPowerAction.init(rawValue:)) }
    public init(actions: [String], authorizationRequired: Bool) {
        self.actions = actions; self.authorizationRequired = authorizationRequired
    }
}
