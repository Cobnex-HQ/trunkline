#if canImport(TrunklineCore)
import TrunklineCore
#endif
import SwiftUI

struct PowerControlsAuthorizationView: View {
    @State private var capability: MacPowerCapability?
    @State private var checking = false
    var body: some View {
        Section("Remote power controls") {
            LabeledContent("Restart, shut down and log out") {
                if checking || capability == nil { ProgressView().controlSize(.small) }
                else {
                    Text(capability?.availableActions.count == MacPowerAction.allCases.count ? "Ready" :
                        capability?.authorizationRequired == true ? "Needs approval" : "Unavailable")
                        .foregroundStyle(.secondary)
                }
            }
            if capability?.authorizationRequired == true {
                HStack {
                    Button("Allow power controls") { Task { await refresh(allowPrompt: true) } }
                    Button("Automation settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }.disabled(checking)
            }
            Text("Your paired device asks for confirmation before ending the Mac session. Apps may still ask to save work on the desktop.")
                .font(.caption).foregroundStyle(.secondary)
        }.task { await refresh(allowPrompt: false) }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                Task { await refresh(allowPrompt: false) }
            }
    }
    @MainActor private func refresh(allowPrompt: Bool) async {
        guard !checking else { return }
        checking = true
        let result = await Task.detached(priority: .utility) { HostPower().capability(allowPrompt: allowPrompt) }.value
        capability = result; checking = false
    }
}
