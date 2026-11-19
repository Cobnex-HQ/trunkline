import SwiftUI
import TrunklineCore

struct ConnectionHealthOverlay: View {
    let health: ConnectionHealth
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(health.route.rawValue, systemImage: health.route == .away ? "globe" : "network")
                .font(.caption.weight(.medium))
            HStack(alignment: .top, spacing: 16) {
                metric("Mac RTT", health.roundTripMS.map { "\($0) ms" } ?? "—")
                metric("Frame loss", health.frameLossPercent.map { String(format: "%.1f%%", $0) } ?? "—")
                metric("Video target", health.videoMbps.map { String(format: "%.1f Mbps", $0) } ?? "—")
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("connection-health")
        .allowsHitTesting(false)
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.caption.monospacedDigit())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
