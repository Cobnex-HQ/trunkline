import Foundation

/// Owned by the host's serial actor. Only the connection holding the lease may release it.
public struct SessionAdmission {
    public enum Result: Equatable { case accepted, busy, invalidCredentials }
    public private(set) var owner: UUID?
    public init() {}
    public mutating func admit(_ id: UUID, verify: () -> Bool) -> Result {
        guard owner == nil else { return .busy }
        guard verify() else { return .invalidCredentials }
        owner = id
        return .accepted
    }
    public mutating func release(_ id: UUID) {
        if owner == id { owner = nil }
    }
}
