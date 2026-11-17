import SwiftUI

/// Available before pairing and from the connected Mac menu.
struct AppHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Install and open the Trunkline host on your Mac.", systemImage: "desktopcomputer")
                    Label("Allow screen recording and input control on the Mac, then start access.", systemImage: "hand.point.up.left")
                    Label("Scan the Mac’s QR code and enter its connection passcode here.", systemImage: "qrcode.viewfinder")
                    Link("Mac setup guide", destination: URL(string: "https://github.com/Cobnex-HQ/trunkline#readme")!)
                } header: { Text("Connect your Mac") } footer: {
                    Text("Requires a Mac running macOS 15 or later. Start on the same local network. Away access must be configured and tested before you leave.")
                }
                Section("Using the desktop") {
                    Text("Tap to move the pointer and click. Pinch to zoom. Rotate your device for a wider view.")
                    Text("Use Keyboard for typing and Spaces and windows for Mission Control, desktop switching and available displays.")
                }
                Section("Privacy") {
                    Text("The Mac runs your apps and terminal commands. Trunkline sends your input and streams the display. Save a passcode only on a device you trust.")
                    Link("Privacy notice", destination: URL(string: "https://github.com/Cobnex-HQ/trunkline/blob/main/docs/PRIVACY.md")!)
                    Link("Open-source acknowledgments", destination: URL(string: "https://github.com/Cobnex-HQ/trunkline/blob/main/docs/THIRD_PARTY.md")!)
                }
                Section {
                    Link("Get help or report a problem", destination: URL(string: "https://github.com/Cobnex-HQ/trunkline/issues")!)
                } footer: {
                    Text("Remove passcodes, pairing links and personal information before posting a public issue.")
                }
            }
            .navigationTitle("Help and privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
