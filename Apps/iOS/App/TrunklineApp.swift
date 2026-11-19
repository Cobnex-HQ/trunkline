import SwiftUI
#if canImport(TrunklineCore)
import TrunklineCore
#endif

@main
@MainActor
struct TrunklineApp: SwiftUI.App {
    var body: some Scene {
        WindowGroup(id: "workspace") { WorkspaceScene() }
        WindowGroup("Mac", id: "mac", for: String.self) { $macID in
            WorkspaceScene(initialMacID: macID)
        }
    }
}

@MainActor
private enum WorkspaceModels {
    static var createdFirstWindow = false
    static func make(macID: String?) -> ConnectionModel {
        let first = !createdFirstWindow && macID == nil
        createdFirstWindow = true
        let model = ConnectionModel(automaticallyResume: first,
            resumeStorageKey: first ? "resume-mac-id" : "resume-mac-id.window.\(macID ?? UUID().uuidString)")
        if let macID { model.selectMac(macID) }
        return model
    }
}

@MainActor
struct WorkspaceScene: View {
    @StateObject private var model: ConnectionModel
    init(initialMacID: String? = nil) {
        _model = StateObject(wrappedValue: WorkspaceModels.make(macID: initialMacID))
    }
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
    var body: some View {
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
            .background(WindowFocusReader(changed: { model.setWindowFocused($0) }, disconnected: { model.applicationDidEnterBackground() }))
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TrunklineDesktopStopped"))) { _ in model.refreshAwakeState() }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in model.refreshSavedMacs() }
            .tint(Color("AccentColor"))
            .preferredColorScheme(selectedAppearance.colorScheme)
            .overlay {
                if scenePhase != .active {
                    Color(uiColor: .systemBackground).ignoresSafeArea()
                        .overlay { Label("Trunkline", systemImage: "lock.shield").font(.title) }
                }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .inactive { model.files.clipboard.pause() }
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
