import Foundation

/// Uses fresh video-loss samples, not loopback RTT or static desktop frame rate.
/// Decrease after two bad samples. Recover only after 20 healthy seconds.
public struct AdaptiveStreamPolicy: Sendable {
    public private(set) var currentKbps: Int
    public let maximumKbps: Int
    private var lastSample: Double?
    private var lastChange = -Double.infinity
    private var healthySince: Double?
    private var badSamples = 0
    public init(maximumKbps: Int) {
        self.maximumKbps = max(1000, min(100_000, maximumKbps))
        currentKbps = self.maximumKbps
    }
    public mutating func observe(loss: Double, sampleTime: Double, now: Double) -> Int? {
        guard loss.isFinite, (0...1).contains(loss), sampleTime.isFinite, now.isFinite,
              now >= sampleTime, now - sampleTime <= 3,
              lastSample.map({ sampleTime > $0 }) ?? true else { return nil }
        if let lastSample, sampleTime - lastSample > 4 { healthySince = nil; badSamples = 0 }
        lastSample = sampleTime
        if loss >= 0.03 {
            healthySince = nil
            badSamples += 1
            guard badSamples >= 2, now - lastChange >= 10 else { return nil }
            return change(to: max(1000, currentKbps * 7 / 10), at: now)
        }
        badSamples = 0
        guard loss <= 0.005 else { healthySince = nil; return nil }
        if healthySince == nil { healthySince = sampleTime }
        guard sampleTime - healthySince! >= 20, now - lastChange >= 20 else { return nil }
        return change(to: min(maximumKbps, currentKbps + max(100, currentKbps / 10)), at: now)
    }
    private mutating func change(to value: Int, at time: Double) -> Int? {
        guard value != currentKbps else { return nil }
        currentKbps = value; lastChange = time; healthySince = nil; badSamples = 0
        return value
    }
}

/// The token binds requests to the active encoder session. Older hosts omit this capability.
public struct DesktopQualityState: Codable, Equatable, Sendable {
    public var session: UInt64
    public var maximum: Int
    public var requested: Int
    public var applied: Int
    public var failed: Bool
    public var isAvailable: Bool { session != 0 && maximum >= 1000 && !failed }
}
