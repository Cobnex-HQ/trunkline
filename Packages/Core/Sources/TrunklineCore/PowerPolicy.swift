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
