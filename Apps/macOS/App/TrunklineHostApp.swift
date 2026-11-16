#if canImport(TrunklineCore)
import TrunklineCore
#endif
import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins

@main
@MainActor
struct TrunklineHostApp: App {
    @NSApplicationDelegateAdaptor(HostAppDelegate.self) private var delegate
    private var model: HostModel { delegate.model }
    @AppStorage("trunkline.appearance") private var appearance: AppAppearance = .system
    var body: some Scene {
        WindowGroup("Trunkline", id: "host") {
            HostView(model: model)
                .tint(Color("AccentColor"))
                .preferredColorScheme(appearance.colorScheme)
                .frame(minWidth: 700, minHeight: 480)
        }
        .defaultSize(width: 860, height: 560)
        .windowResizability(.automatic)
        .windowToolbarStyle(.unified)
        MenuBarExtra {
            HostMenu(model: model)
        } label: {
            HostMenuLabel(model: model)
        }
    }
}

private struct HostMenuLabel: View {
    @ObservedObject var model: HostModel
    var body: some View {
        Label("Trunkline", systemImage: model.isConnected ? "iphone.radiowaves.left.and.right" : "laptopcomputer")
    }
}

private struct HostMenu: View {
    @ObservedObject var model: HostModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.status)
        Divider()
        Button("Open Trunkline") { openWindow(id: "host"); NSApp.activate(ignoringOtherApps: true) }
        if model.isConnected { Button("Disconnect device") { model.disconnect() } }
        if model.isRunning { Button("Stop remote access") { model.stop() } }
        Divider()
        Button("Quit") { NSApplication.shared.terminate(nil) }
    }
}

struct HostView: View {
    @ObservedObject var model: HostModel
    @State private var passcode = ""
    @State private var confirmation = ""
    private enum Panel: String, CaseIterable, Identifiable {
        case connection = "Connection", desktop = "Desktop", power = "Power", settings = "Settings"
        var id: Self { self }
        var symbol: String {
            switch self { case .connection: "iphone.radiowaves.left.and.right"; case .desktop: "display"; case .power: "bolt"; case .settings: "gearshape" }
        }
    }
    @State private var panel: Panel? = .connection
    @State private var editAddress = false
    @State private var authorizing = false
    private var needsCredentials: Bool { model.error?.contains("credentials") == true }

    var body: some View {
        NavigationSplitView {
            List(Panel.allCases, selection: $panel) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    Image("ElephantLogo").resizable().scaledToFit().frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trunkline").font(.headline)
                        Text(model.isConnected ? "Connected" : model.isRunning ? "Available" : "Offline").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(16)
            }
        } detail: {
            VStack(spacing: 0) {
                if needsCredentials && (panel ?? .connection) != .connection {
                    HostCredentialNotice { panel = .connection }
                } else if let error = model.error, !needsCredentials {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(error).textSelection(.enabled)
                        Spacer()
                        Button("Dismiss", systemImage: "xmark") { model.error = nil }.labelStyle(.iconOnly)
                    }.padding(20).background(Color.orange.opacity(0.08))
                }
                Group {
                    switch panel ?? .connection {
                    case .connection:
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                HStack(spacing: 12) {
                                    Image(systemName: "laptopcomputer").font(.title2)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(Host.current().localizedName ?? "This Mac").font(.headline)
                                        Text(model.status).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Divider()
                                if needsCredentials { credentialStep }
                                else if !model.isRunning { secureStep }
                                else {
                                    if model.isConnected { desktopStep }
                                    connectStep
                                }
                            }.padding(22).frame(maxWidth: 780, alignment: .leading).frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    case .desktop:
                        Form { DesktopSharingView(engine: model.sunshine, enabled: model.isRunning) }
                            .formStyle(.grouped)
                    case .power:
                        Form {
                            KeepAwakeView(manager: model.keepAwake)
                            PowerControlsAuthorizationView()
                        }.formStyle(.grouped)
                    case .settings: settingsContent
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle((panel ?? .connection).rawValue)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if model.isRunning || model.isStarting {
                        Button(model.isStarting ? "Cancel" : "Stop access") { model.stop() }
                    } else if model.hasPasscode && !needsCredentials {
                        Button("Start access") { Task { await model.start() } }.buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    private var credentialStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Allow access to saved credentials", systemImage: "key.fill")
                .font(.headline)
            Text("Approve Trunkline’s access on this Mac.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(authorizing ? "Waiting for approval…" : "Authorize access…") {
                    authorizing = true
                    Task {
                        await model.authorizeCredentials()
                        authorizing = false
                    }
                }
                .buttonStyle(.borderedProminent).disabled(authorizing)
                if authorizing { ProgressView().controlSize(.small) }
            }
            Text("Future connections authenticate on your phone.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var secureStep: some View {
        let guidance = PairingGuidance.nextStep(hasPasscode: model.hasPasscode, isRunning: model.isRunning)
        return VStack(alignment: .leading, spacing: 16) {
            Text(guidance.title).font(.headline)
            Text(guidance.detail)
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !model.hasPasscode {
                passcodeFields
            } else {
                Label("Connection passcode saved", systemImage: "checkmark.shield.fill").foregroundStyle(.green)
            }
            if model.isStarting {
                HStack { ProgressView().controlSize(.small); Text(model.status) }
            } else if model.hasPasscode {
                Button(guidance.actionTitle) { Task { await model.start() } }
                .buttonStyle(.borderedProminent).controlSize(.regular)
                .disabled(!model.hasPasscode)
            }
            Label("Passcode required", systemImage: "lock.fill")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    var passcodeFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            SecureField("New connection passcode", text: $passcode)
            SecureField("Confirm passcode", text: $confirmation)
            Text(passcode.utf8.count > 64 ? "This passcode is too long. Use fewer characters." : "Use 8–64 characters.")
                .font(.caption).foregroundStyle(.secondary)
            if !confirmation.isEmpty && confirmation != passcode {
                Text("The passcodes don’t match yet.").font(.caption).foregroundStyle(.secondary)
            }
            Button(model.hasPasscode ? "Save new passcode" : "Start access") {
                model.savePasscode(passcode)
                if model.error == nil {
                    passcode = ""; confirmation = ""
                    if panel != .settings { Task { await model.start() } }
                }
            }.disabled(!(8...64).contains(passcode.utf8.count) || passcode != confirmation)
        }.textFieldStyle(.roundedBorder).controlSize(.regular).frame(maxWidth: 400, alignment: .leading)
    }

    var connectStep: some View {
        return VStack(alignment: .leading, spacing: 18) {
            if !model.pairingLink.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) {
                    PairingQRCode(link: model.pairingLink)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pair a device").font(.headline)
                        Text("In Trunkline, tap Scan QR code.")
                            .foregroundStyle(.secondary)
                        HostStatusPill(title: model.away.ticket == nil ? "Same Wi-Fi" : "Wi-Fi or away", tint: .accentColor)
                    }
                    Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        PairingQRCode(link: model.pairingLink).frame(maxWidth: .infinity)
                        Text("In Trunkline, tap Scan QR code.")
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Away access · Beta", systemImage: "network")
                    Spacer()
                    if model.away.enabled {
                        Button("Turn off") { model.away.disable() }
                        if model.away.ticket == nil && !model.away.busy { Button("Retry") { model.away.start() } }
                    } else { Button("Enable") { model.away.enable() }.disabled(!model.isRunning) }
                }
                Text(model.away.status).font(.callout).foregroundStyle(.secondary)
                Text("Scan the updated QR code after enabling.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("Pairing link", isExpanded: $editAddress) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Mac address", text: $model.address).textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Copy link") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(model.pairingLink, forType: .string)
                        }
                        ShareLink("Share link", item: model.pairingLink)
                    }
                    Text("Keep your pairing link private.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 12)
            }
        }
    }

    var desktopStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Device connected", systemImage: "checkmark.circle.fill").font(.title2.bold()).foregroundStyle(.green)
            Text("Desktop, apps, terminal and files are available on your device.")
                .foregroundStyle(.secondary)
        }
    }

    var settingsContent: some View {
        Form {
            Section("Appearance") { AppearancePicker() }
            Section("Connection passcode") { passcodeFields }
            Section("Files") {
                LabeledContent("Shared folder", value: model.sharedFolderPath.isEmpty ? "None" : model.sharedFolderPath)
                Button("Choose folder…") { model.chooseSharedFolder() }
                Text("Only this folder is shared. Changing it stops access.").font(.caption).foregroundStyle(.secondary)
            }
            Section("About") {
                LabeledContent("Trunkline", value: "Open source")
                Link("Privacy notice", destination: URL(string: "https://github.com/Cobnex-HQ/trunkline/blob/main/docs/PRIVACY.md")!)
                Link("Open-source acknowledgments", destination: URL(string: "https://github.com/Cobnex-HQ/trunkline/blob/main/docs/THIRD_PARTY.md")!)
            }
        }.formStyle(.grouped)
    }



}

private struct PairingQRCode: View {
    let link: String
    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image).interpolation(.none).resizable().scaledToFit()
            } else {
                Image(systemName: "qrcode").font(.largeTitle)
            }
        }
        .frame(width: 180, height: 180).padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel("Pairing QR code. Copy or share the pairing link if you cannot scan it.")
    }
    private var image: NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(link.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let raster = CIContext().createCGImage(output.transformed(by: CGAffineTransform(scaleX: 6, y: 6)),
                                                     from: output.extent.applying(CGAffineTransform(scaleX: 6, y: 6))) else { return nil }
        return NSImage(cgImage: raster, size: NSSize(width: raster.width, height: raster.height))
    }
}

private struct HostStatusPill: View {
    let title: String
    var tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

