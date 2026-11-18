import SwiftUI

/// Available before pairing and from the connected Mac menu.
struct AppHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image("ElephantLogo").resizable().scaledToFit().frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
                        VStack(alignment: .leading) {
                            Text("Trunkline").font(.headline)
                            Text("Your Mac, within reach.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                }
                Section {
                    setupStep(1, title: "Open Trunkline", detail: "Install and open the Trunkline host on your Mac.")
                    setupStep(2, title: "Turn on sharing", detail: "Allow screen recording and input control on the Mac, then turn on My Mac → Sharing.")
                    setupStep(3, title: "Pair your device", detail: "Scan the Mac’s QR code and enter its connection passcode here.")
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
                } header: { Text("Support") } footer: {
                    Text("Remove passcodes, pairing links and personal information before posting a public issue.")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: 700).frame(maxWidth: .infinity)
            .background(Color.workspaceBackground)
            .navigationTitle("Help and privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private func setupStep(_ number: Int, title: String, detail: String) -> some View {
        Label {
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(detail).font(.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "\(number).circle").foregroundStyle(.tint)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
