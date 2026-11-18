import SwiftUI
#if canImport(TrunklineCore)
import TrunklineCore
#endif

struct ConnectView: View {
    @ObservedObject var model: ConnectionModel
    @State private var scanner = false
    @State private var manual = false
    @State private var forget = false
    @State private var passcodeFocused = false
    @State private var usePasscode = false
    @State private var settings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var pairing: PairingDetails? { try? PairingDetails.parse(model.pairingText) }
    private var connecting: Bool { model.phase != .setup }
    private var compactConnection: Bool { verticalSizeClass == .compact && pairing != nil }
    private var savedUnlock: Bool { model.canUnlockSaved && model.passcode.isEmpty && !connecting && !usePasscode }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    if !compactConnection {
                        Section { brandHeader }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: verticalSizeClass == .compact ? 0 : 8, leading: 0,
                                                     bottom: verticalSizeClass == .compact ? 0 : 8, trailing: 0))
                    }

                    if pairing == nil {
                        if !model.savedMacs.isEmpty {
                            Section { macSelector }
                        }
                        Section {
                            Button { scanner = true } label: {
                                Label("Scan QR code", systemImage: "qrcode.viewfinder")
                                    .frame(maxWidth: .infinity, minHeight: 36)
                            }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.roundedRectangle)
                            .tint(Color("ControlSurface"))
                            .foregroundStyle(.white)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())

                        Section {
                            DisclosureGroup("Pairing link", isExpanded: $manual) {
                                TextField("trunkline://…", text: $model.pairingText, axis: .vertical)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                PasteButton(payloadType: String.self) { values in
                                    if let value = values.first,
                                       let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                                        model.receivePairingLink(url)
                                    }
                                }
                            }
                        } footer: {
                            Text("You can also paste a pairing link from your Mac.")
                        }
                    } else {
                        Section {
                            macSelector
                            if model.hasAwayAccess {
                                Picker("Route", selection: $model.useAwayAccess) {
                                    Text("Local Wi-Fi").tag(false)
                                    Text("Away").tag(true)
                                }
                                .pickerStyle(.segmented)
                                .disabled(connecting)
                            }
                        }

                        if savedUnlock {
                            Section { Toggle("Save passcode", isOn: $model.rememberPasscode) }
                        } else {
                            Section {
                                ConnectionPasscodeField(text: $model.passcode, focused: $passcodeFocused,
                                                        enabled: !connecting, submit: connect)
                                    .id("connection-passcode")
                                if !connecting {
                                    Toggle("Save passcode", isOn: $model.rememberPasscode)
                                }
                            } footer: {
                                if !connecting && verticalSizeClass != .compact {
                                    Text("Use the connection passcode shown on your Mac.")
                                }
                            }
                        }

                        Section {
                            if connecting {
                                connectionProgress
                            } else {
                                Button {
                                    if savedUnlock { Task { await model.unlockSaved() } }
                                    else { connect() }
                                } label: {
                                    Text(savedUnlock ? "Unlock and connect" : "Connect")
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                }
                                .buttonStyle(.borderedProminent)
                                .buttonBorderShape(.roundedRectangle)
                                .tint(Color("ControlSurface"))
                                .foregroundStyle(.white)
                                .disabled(!savedUnlock && model.passcode.isEmpty)
                                if savedUnlock {
                                    Button("Use passcode instead") {
                                        usePasscode = true
                                        passcodeFocused = true
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                    }

                    if let error = model.error {
                        Section {
                            Label { Text(error).textSelection(.enabled) } icon: {
                                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                            }
                            Button("Device settings") {
                                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                            }
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: passcodeFocused) { _, focused in
                    if focused { revealPasscode(using: proxy) }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification)) { _ in
                    if passcodeFocused { revealPasscode(using: proxy) }
                }
                .onChange(of: model.selectedMacID) { _, _ in
                    passcodeFocused = false
                    usePasscode = false
                }
                .nativeWorkspaceStyle()
                .listSectionSpacing(verticalSizeClass == .compact ? 8 : 16)
                .contentMargins(.top, verticalSizeClass == .compact ? 0 : 16, for: .scrollContent)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("Trunkline")
                .toolbar {
                    if compactConnection {
                        ToolbarItem(placement: .principal) {
                            HStack(spacing: 8) {
                                Image("ElephantLogo").resizable().scaledToFit()
                                    .frame(width: 24, height: 24)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .accessibilityHidden(true)
                                Text("Trunkline").font(.headline)
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Settings", systemImage: "gearshape") { settings = true }
                    }
                }
                .confirmationDialog("Forget this Mac?", isPresented: $forget, titleVisibility: .visible) {
                    Button("Forget", role: .destructive) { model.forget() }
                }
                .onAppear {
                    if model.openPairingScanner {
                        model.openPairingScanner = false
                        scanner = true
                    }
                }
            }
            .sheet(isPresented: $scanner) {
                PairingScanner { link in
                    if let url = URL(string: link) { model.receivePairingLink(url) }
                }
            }
            .sheet(isPresented: $settings) { ConnectionSettingsView() }
        }
    }

    private var brandHeader: some View {
        let compact = verticalSizeClass == .compact
        let layout = compact ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 14))
        return layout {
            Image("ElephantLogo")
                .resizable().scaledToFit()
                .frame(width: compact ? 36 : 64, height: compact ? 36 : 64)
                .clipShape(RoundedRectangle(cornerRadius: compact ? 8 : 15))
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("Connect to your Mac").font(.title3.weight(.semibold))
                if pairing == nil {
                    Text("Scan the QR code shown in Trunkline on your Mac.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 0 : 12)
    }

    private var macSelector: some View {
        Menu {
            ForEach(model.savedMacs) { mac in
                Button {
                    if model.selectedMacID != mac.id { model.selectMac(mac.id) }
                } label: {
                    if model.selectedMacID == mac.id { Label(mac.name, systemImage: "checkmark") }
                    else { Text(mac.name) }
                }
            }
            Divider()
            Button("Scan another Mac", systemImage: "qrcode.viewfinder") { scanner = true }
            if pairing != nil {
                Button("Forget Mac", role: .destructive) { forget = true }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "desktopcomputer").font(.title2).foregroundStyle(.tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(pairing == nil ? "Choose a saved Mac" : model.name)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(pairing == nil ? "Your Macs" : model.useAwayAccess ? "Away access" : "Local network")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, verticalSizeClass == .compact ? 0 : 6)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Connection options")
        .accessibilityValue(model.name)
        .disabled(connecting)
    }

    private var connectionProgress: some View {
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            GlacierLoadingIndicator(size: 24)
            Text(model.connectionStatus).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            if !textSize.isAccessibilitySize { Spacer() }
            Button("Cancel") { model.disconnect() }.frame(minHeight: 44)
        }
    }

    private func revealPasscode(using proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            proxy.scrollTo("connection-passcode", anchor: .center)
        }
    }

    private func connect() {
        passcodeFocused = false
        model.connect()
    }
}

private struct ConnectionSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var help = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") { AppearancePicker() }
                Section("Support") {
                    Button("Help and Mac setup", systemImage: "questionmark.circle") { help = true }
                    Link("Privacy notice", destination: URL(string: "https://github.com/Cobnex-HQ/trunkline/blob/main/docs/PRIVACY.md")!)
                    Link("Open-source acknowledgments", destination: URL(string: "https://github.com/Cobnex-HQ/trunkline/blob/main/docs/THIRD_PARTY.md")!)
                }
            }
            .nativeWorkspaceStyle()
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $help) { AppHelpView() }
        }
    }
}
