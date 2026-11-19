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
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .background { model.applicationDidEnterBackground() }
                else if phase == .active {
                    // Face ID temporarily makes the scene inactive. Do not cancel
                    // its unlock task during that transition. The model rejects
                    // stale results if the app actually enters the background.
                    Task {
                        guard UIApplication.shared.applicationState == .active else { return }
                        await model.applicationDidBecomeActive()
                    }
                }
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

struct ClipboardView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ObservedObject var files: ClientFiles
    @State private var outgoing = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                TrunklineSection("Send to Mac") {
                    TextEditor(text: $outgoing).frame(minHeight: verticalSizeClass == .compact ? 96 : 160).accessibilityLabel("Clipboard text")
                    PasteButton(payloadType: String.self) { outgoing = $0.joined(separator: "\n") }
                    Button("Copy to Mac", systemImage: "arrow.up.doc") {
                        files.clipboardError = nil
                        files.send?(.setClipboard(outgoing))
                    }.disabled(outgoing.isEmpty || outgoing.utf16.count > 65536)
                }
                TrunklineSection("Mac clipboard") {
                    Text(files.clipboardText.isEmpty ? "The Mac clipboard contains no text." : files.clipboardText)
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    Button("Copy to this device", systemImage: "doc.on.doc") { UIPasteboard.general.string = files.clipboardText }
                        .disabled(files.clipboardText.isEmpty)
                }
                if let error = files.clipboardError {
                    TrunklineSection {
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
            .background(Color.workspaceBackground)
            .navigationTitle("Clipboard")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
