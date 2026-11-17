import SwiftUI
#if canImport(TrunklineCore)
import TrunklineCore
#endif

@main
@MainActor
struct TrunklineApp: SwiftUI.App {
    @StateObject private var model = ConnectionModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("trunkline.appearance") private var appearance: AppAppearance = .system
    private var selectedAppearance: AppAppearance {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-review"),
           let value = ProcessInfo.processInfo.environment["TRUNKLINE_REVIEW_APPEARANCE"],
           let preview = AppAppearance(rawValue: value) { return preview }
        #endif
        return appearance
    }
    private var regularContent: some View {
        Group {
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--ui-review") { ExperienceReview() }
            else { workspaceContent }
            #else
            workspaceContent
            #endif
        }
    }
    private var workspaceContent: some View {
        Group {
            if model.phase == .connected { ConnectedTabs(model: model) }
            else { ConnectView(model: model) }
        }
    }
    var body: some Scene {
        WindowGroup {
            Group {
                regularContent
            }
            .task {
                model.startRouteMonitoring()
                #if DEBUG
                if let raw = ProcessInfo.processInfo.environment["TRUNKLINE_PAIRING_IMPORT"], let url = URL(string: raw) {
                    model.receivePairingLink(url); model.useAwayAccess = true
                }
                #endif
            }
            .tint(Color("AccentColor"))
            .preferredColorScheme(selectedAppearance.colorScheme)
            .overlay {
                if scenePhase != .active {
                    Color(uiColor: .systemBackground).ignoresSafeArea()
                        .overlay { Label("Trunkline", systemImage: "lock.shield").font(.title) }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { model.disconnect() }
                else if phase == .active { model.checkLocalRoute() }
            }
            .onOpenURL { url in
                guard model.phase == .setup else { return }
                model.receivePairingLink(url)
            }
            .alert("Use Away access?", isPresented: $model.offerAwayAccess) {
                Button("Use Away") { model.chooseAwayAccess() }
                Button("Stay local", role: .cancel) {}
            } message: {
                Text("Your Mac isn’t reachable locally on this network. Try Away access, including on another Wi-Fi network.")
            }
            .alert("Connection", isPresented: Binding(get: { model.phase == .connected && model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK") { model.error = nil }
            } message: { Text(model.error ?? "") }
        }
    }
}

struct ConnectView: View {
    @ObservedObject var model: ConnectionModel
    @State private var scanner = false
    @State private var manual = false
    @State private var forget = false
    @State private var passcodeFocused = false
    @State private var usePasscode = false
    @State private var showHelp = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    private var pairing: PairingDetails? { try? PairingDetails.parse(model.pairingText) }
    private var connecting: Bool { model.phase != .setup }
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image("ElephantLogo").resizable().scaledToFit().frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 9)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pairing == nil ? "Pair your Mac" : model.name).font(.headline)
                            Text(pairing?.host ?? "Scan its QR code to connect.").font(.subheadline).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }.padding(.vertical, 4)
                }
                if pairing == nil {
                    Section {
                        Button("Scan QR code", systemImage: "qrcode.viewfinder") { scanner = true }
                        DisclosureGroup("Pairing link", isExpanded: $manual) {
                            TextField("trunkline://…", text: $model.pairingText, axis: .vertical)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                            PasteButton(payloadType: String.self) { values in
                                if let value = values.first, let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) { model.receivePairingLink(url) }
                            }
                        }
                    } footer: { Text("Open Trunkline on your Mac to show its QR code.") }
                } else {
                    Section("Connection") {
                        if model.hasAwayAccess {
                            Picker("Route", selection: $model.useAwayAccess) {
                                Text("Local Wi-Fi").tag(false); Text("Away").tag(true)
                            }.pickerStyle(.segmented).disabled(connecting)
                        }
                        if model.canUnlockSaved && model.passcode.isEmpty && !connecting && !usePasscode {
                            Button { Task { await model.unlockSaved() } } label: {
                                Label("Unlock and connect", systemImage: "lock.open").foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, minHeight: 32)
                            }.buttonStyle(.borderedProminent).tint(Color("ControlSurface"))
                            Button("Use passcode instead") { usePasscode = true; passcodeFocused = true }
                            Toggle("Save passcode", isOn: $model.rememberPasscode)
                        } else {
                            ConnectionPasscodeField(text: $model.passcode, focused: $passcodeFocused,
                                                    enabled: !connecting, submit: connect)
                                .id("connection-passcode")
                            if !connecting {
                                Toggle("Save passcode", isOn: $model.rememberPasscode)
                                Button(action: connect) {
                                    Text("Connect").frame(maxWidth: .infinity, minHeight: 32)
                                }.buttonStyle(.borderedProminent).tint(Color("ControlSurface")).disabled(model.passcode.isEmpty)
                            }
                        }
                        if connecting {
                            let statusLayout = textSize.isAccessibilitySize
                                ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout())
                            statusLayout {
                                GlacierLoadingIndicator()
                                Text(model.connectionStatus).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                                if !textSize.isAccessibilitySize { Spacer() }
                                Button("Cancel") { model.disconnect() }.frame(minHeight: 44)
                            }
                        }
                    }
                }
                if !model.savedMacs.isEmpty {
                    Section("My Macs") {
                        ForEach(model.savedMacs) { mac in
                            Button { model.selectMac(mac.id) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "desktopcomputer")
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(mac.name).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                                        if let address = try? PairingDetails.parse(mac.link).host {
                                            Text(address).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if model.selectedMacID == mac.id { Image(systemName: "checkmark").accessibilityLabel("Selected") }
                                }.frame(minHeight: 44)
                            }.disabled(connecting)
                        }
                        Button("Add Mac", systemImage: "plus") { scanner = true }.disabled(connecting)
                    }
                }
                if let error = model.error {
                    Section {
                        Text(error).foregroundStyle(.orange).textSelection(.enabled)
                        Button("Device settings") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                    }
                }
                Section("Appearance") { AppearancePicker() }
                Section("Support") {
                    Button("Help and Mac setup", systemImage: "questionmark.circle") { showHelp = true }
                    Link("Privacy notice", destination: URL(string: "https://github.com/Cobnex-HQ/trunkline/blob/main/docs/PRIVACY.md")!)
                    Link("Open-source acknowledgments", destination: URL(string: "https://github.com/Cobnex-HQ/trunkline/blob/main/docs/THIRD_PARTY.md")!)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: passcodeFocused) { _, focused in
                if focused { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo("connection-passcode", anchor: .center) } }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification)) { _ in
                if passcodeFocused { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo("connection-passcode", anchor: .center) } }
            }
            .onChange(of: model.selectedMacID) { _, _ in passcodeFocused = false; usePasscode = false }
            .formStyle(.grouped)
            .nativeWorkspaceStyle()
            .frame(maxWidth: 600).frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Trunkline")
            .toolbar {
                if pairing != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Scan another Mac", systemImage: "qrcode.viewfinder") { scanner = true }
                            Button("Forget Mac", role: .destructive) { forget = true }
                        } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Connection options").disabled(connecting)
                    }
                }
            }
            .confirmationDialog("Forget this Mac?", isPresented: $forget, titleVisibility: .visible) {
                Button("Forget", role: .destructive) { model.forget() }
            }
            .onAppear {
                if model.openPairingScanner { model.openPairingScanner = false; scanner = true }
            }
            }
            .sheet(isPresented: $scanner) { PairingScanner { link in if let url = URL(string: link) { model.receivePairingLink(url) } } }
            .sheet(isPresented: $showHelp) { AppHelpView() }
        }
    }
    private func connect() { passcodeFocused = false; model.connect() }
}

struct ClipboardView: View {
    @ObservedObject var files: ClientFiles
    @State private var outgoing = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Send to Mac") {
                    TextEditor(text: $outgoing).frame(minHeight: 160).accessibilityLabel("Clipboard text")
                    PasteButton(payloadType: String.self) { outgoing = $0.joined(separator: "\n") }
                    Button("Copy to Mac", systemImage: "arrow.up.doc") {
                        files.clipboardError = nil
                        files.send?(.setClipboard(outgoing))
                    }.disabled(outgoing.isEmpty || outgoing.utf16.count > 65536)
                }
                Section("Mac clipboard") {
                    Text(files.clipboardText.isEmpty ? "The Mac clipboard contains no text." : files.clipboardText)
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    Button("Copy to this device", systemImage: "doc.on.doc") { UIPasteboard.general.string = files.clipboardText }
                        .disabled(files.clipboardText.isEmpty)
                }
                if let error = files.clipboardError {
                    Section {
                        Text(error).foregroundStyle(.orange)
                        Button("Refresh clipboard", systemImage: "arrow.clockwise") {
                            files.clipboardError = nil
                            files.send?(.requestClipboard)
                        }
                    }
                }
            }
            .nativeWorkspaceStyle()
            .frame(maxWidth: 780).frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Clipboard")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
