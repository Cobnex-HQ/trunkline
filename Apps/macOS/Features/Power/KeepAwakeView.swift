#if canImport(TrunklineCore)
import TrunklineCore
#endif
import SwiftUI

struct KeepAwakeView: View {
    @ObservedObject var manager: KeepAwakeManager
    @State private var confirmLid = false
    var body: some View {
        Group {
            Section("Startup") {
                Toggle("Start Trunkline at login", isOn: Binding(get: { manager.loginRequested }, set: { manager.setStartsAtLogin($0) }))
                loginStatus
                Text("After a restart, unlock and log in to this Mac. Connections and terminal sessions end during restart.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section("Keep awake") {
                Picker("Power mode", selection: Binding(get: { manager.mode }, set: { mode in
                    if mode == .lidClosed { confirmLid = true } else { manager.apply(mode) }
                })) { ForEach(AwakeMode.allCases) { mode in Text(mode.title).tag(mode) } }
                Text("Remote sessions keep the Mac and display awake. Closed-lid mode disables system sleep and needs administrator approval; keep the Mac powered and ventilated.")
                    .font(.caption).foregroundStyle(.secondary)
                if manager.needsRecovery {
                    Label("A previous closed-lid session was not shut down cleanly.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    HStack {
                        Button("Restore previous sleep settings") { manager.recover() }
                        Button("Continue keeping awake") { manager.continueRecoveredSession() }
                    }
                }
            }
        }
        .onAppear { manager.refreshLoginStatus() }
        .confirmationDialog("Keep this Mac awake with its lid closed?", isPresented: $confirmLid, titleVisibility: .visible) {
            Button("Enable closed-lid mode") { manager.apply(.lidClosed) }
        } message: { Text("macOS will ask for administrator authorization. Trunkline restores your previous sleep setting when you turn this off or quit. After a crash, restore it here on the next launch.") }
        .alert("Power settings", isPresented: Binding(get: { manager.error != nil }, set: { if !$0 { manager.error = nil } })) {
            Button("OK") { manager.error = nil }
        } message: { Text(manager.error ?? "") }
    }
    @ViewBuilder private var loginStatus: some View {
        switch manager.loginStatus {
        case .enabled:
            Label("Starts automatically after login", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary).font(.callout)
        case .requiresApproval:
            Label("Approval needed in Login Items", systemImage: "exclamationmark.circle")
                .foregroundStyle(.orange).font(.callout)
            Button("Open Login Items…") { manager.openLoginSettings() }
        case .notRegistered:
            Text("Open Trunkline manually after login.").font(.callout).foregroundStyle(.secondary)
        case .notFound:
            Label("Startup item unavailable", systemImage: "exclamationmark.circle")
                .foregroundStyle(.orange).font(.callout)
            Text("Keep Trunkline in Applications, then try enabling startup again.")
                .font(.caption).foregroundStyle(.secondary)
        @unknown default:
            Text("Check startup status in System Settings.").font(.callout).foregroundStyle(.secondary)
            Button("Open Login Items…") { manager.openLoginSettings() }
        }
    }

}
