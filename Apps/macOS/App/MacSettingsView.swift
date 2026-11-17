import SwiftUI
import TrunklineCore

struct MacSettingsView: View {
    var body: some View {
        Form {
            Section("Appearance") { AppearancePicker() }
            Section("About") {
                HStack(spacing: 12) {
                    Image("ElephantLogo").resizable().scaledToFit().frame(width: 40, height: 40).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Trunkline").font(.headline)
                        Text("Open source remote access for your Macs.").foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 4)
                Link("Privacy notice", destination: URL(string: "https://github.com/Cobnex-HQ/trunkline/blob/main/docs/PRIVACY.md")!)
                Link("Open-source acknowledgments", destination: URL(string: "https://github.com/Cobnex-HQ/trunkline/blob/main/docs/THIRD_PARTY.md")!)
            }
        }.formStyle(.grouped)
    }
}
