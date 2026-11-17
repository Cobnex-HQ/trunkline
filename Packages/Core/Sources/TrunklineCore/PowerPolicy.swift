import Foundation

public enum AwakeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case off, system, systemAndDisplay, lidClosed
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .off: "Allow normal sleep"
        case .system: "Keep system awake"
        case .systemAndDisplay: "Keep system and display awake"
        case .lidClosed: "Keep awake with lid closed"
        }
    }
}

public struct MacAwakeState: Codable, Equatable, Sendable {
    public let mode: AwakeMode
    public let sessionActive: Bool
    public let awayAccessActive: Bool
    public let requiresLocalChange: Bool
    public init(mode: AwakeMode, sessionActive: Bool, awayAccessActive: Bool, requiresLocalChange: Bool) {
        self.mode = mode
        self.sessionActive = sessionActive
        self.awayAccessActive = awayAccessActive
        self.requiresLocalChange = requiresLocalChange
    }
}
/// Plan separately from the privileged operation so cancellation never commits state.
public struct PowerTransition: Equatable, Sendable {
    public let changeDisabled: Bool?
    public let savedOriginal: Bool?
    public init(mode: AwakeMode, systemDisabled: Bool, originalDisabled: Bool?) {
        if mode == .lidClosed {
            savedOriginal = originalDisabled ?? systemDisabled
            changeDisabled = systemDisabled ? nil : true
        } else {
            savedOriginal = nil
            changeDisabled = originalDisabled.flatMap { $0 == systemDisabled ? nil : $0 }
        }
    }
}
