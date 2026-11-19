import SwiftUI
import TrunklineCore

struct DeviceAccessView: View {
    @ObservedObject var model: HostModel
    @Environment(\.dismiss) private var dismiss
    @State private var revoking: TrustedDevice?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if model.deviceAccess.requiresApproval {
                        Label("New devices need approval on this Mac", systemImage: "lock.shield")
                    } else {
                        Text("Devices with the connection passcode are trusted when they connect.")
                        Button("Require approval for new devices") { model.requireDeviceApproval() }
                    }
                } footer: {
                    Text("The connection passcode is still required. Device names are supplied by the connecting device.")
                }
                Section("Devices") {
                    if model.deviceAccess.devices.isEmpty {
                        Text("Devices appear after connecting with an updated Trunkline app.").foregroundStyle(.secondary)
                    }
                    ForEach(model.deviceAccess.devices.sorted { $0.lastSeen > $1.lastSeen }) { device in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(device.name).font(.headline)
                                Text(status(device)).foregroundStyle(.secondary)
                                Text(device.lastSeen, format: .dateTime.month().day().hour().minute())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            if device.status != .trusted {
                                Button(device.status == .pending ? "Approve" : "Allow again") { model.approveDevice(device.id) }
                            }
                            if device.status != .revoked {
                                Button("Revoke…", role: .destructive) { revoking = device }
                            }
                        }.padding(.vertical, 4)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Devices")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .disabled(model.updatingDeviceAccess)
            .confirmationDialog("Revoke access?", isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }), presenting: revoking) { device in
                Button("Revoke \(device.name)", role: .destructive) {
                    Task { await model.revokeDevice(device.id) }
                    revoking = nil
                }
            } message: { _ in
                Text("The current connection will end. All desktop pairings will be cleared, so trusted devices must pair their desktop again. New devices will need approval on this Mac. Terminal sessions keep running.")
            }
        }.frame(minWidth: 520, minHeight: 420)
    }
    private func status(_ device: TrustedDevice) -> String {
        switch device.status {
        case .trusted: "Trusted · Last connected"
        case .pending: "Awaiting approval · Requested"
        case .revoked: "Revoked · Last connected"
        }
    }
}
