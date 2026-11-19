import Foundation

/// End-to-end companion RTT, recent video loss and the encoder's target bitrate.
/// A local proxy RTT is never used as a substitute for the Mac's response time.
public struct ConnectionHealth: Equatable, Sendable {
    public let roundTripMS: Int?
    public let frameLossPercent: Double?
    public let videoMbps: Double?
    public let route: ConnectionDiagnostic.Route
    public init(now: TimeInterval, roundTripMS: Int?, roundTripTime: TimeInterval?,
                frameLoss: Double?, videoTime: TimeInterval?, videoKbps: Int?, route: ConnectionDiagnostic.Route) {
        func fresh(_ time: TimeInterval?, within seconds: Double) -> Bool {
            guard let time, time.isFinite, now.isFinite else { return false }
            return now >= time && now - time <= seconds
        }
        self.roundTripMS = fresh(roundTripTime, within: 12) && (roundTripMS ?? -1) >= 0 ? roundTripMS : nil
        frameLossPercent = fresh(videoTime, within: 3) && frameLoss?.isFinite == true && (0...1).contains(frameLoss ?? -1)
            ? frameLoss.map { $0 * 100 } : nil
        videoMbps = fresh(videoTime, within: 3) && (videoKbps ?? 0) > 0 ? videoKbps.map { Double($0) / 1000 } : nil
        self.route = route
    }
}
