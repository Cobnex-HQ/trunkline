import Foundation
import Combine
import TrunklineCore

/// One controller per presented stream. Never sends a new command to an old host.
@MainActor
final class AdaptiveDesktopQuality: ObservableObject {
    private var session: UInt64?
    private var policy: AdaptiveStreamPolicy?
    private var pending: UUID?
    private var stopped = false
    func observe(controls: ClientControls, ceiling: Int, loss: Double, sampleTime: Double, now: Double) {
        guard !stopped, controls.pending == nil, pending == nil,
              let state = controls.snapshot?.desktopQuality, state.isAvailable, state.applied > 0 else { return }
        if session != state.session {
            session = state.session
            policy = AdaptiveStreamPolicy(maximumKbps: min(ceiling, state.maximum))
        }
        guard let kbps = policy?.observe(loss: loss, sampleTime: sampleTime, now: now) else { return }
        controls.perform(.desktopBitrate(session: state.session, kbps: kbps))
        pending = controls.pending
        if pending == nil { stopped = true }
    }
    func receive(_ result: MacControlResult?) {
        guard let result, result.id == pending else { return }
        pending = nil
        if result.error != nil { stopped = true }
    }
}
