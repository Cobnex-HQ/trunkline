import Foundation

public enum StreamPacingMode: String, CaseIterable, Identifiable, Sendable {
    case lowLatency, smooth
    public var id: String { rawValue }
    public var title: String { self == .lowLatency ? "Lowest latency" : "Smoother motion" }
    public var usesFramePacing: Bool { self == .smooth }
}

public enum DesktopInputMode: String, CaseIterable, Identifiable, Sendable {
    case directTouch, trackpad
    public var id: String { rawValue }
    public var title: String { self == .directTouch ? "Direct touch" : "Trackpad" }
    public var detail: String { self == .directTouch ? "Touch exactly where the Mac pointer should go. Pinch to zoom; pan with two fingers." : "One finger moves the pointer; two fingers scroll; press and hold to drag." }
    public var usesAbsolutePointer: Bool { self == .directTouch }
}
