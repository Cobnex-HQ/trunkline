#if canImport(TrunklineCore)
import TrunklineCore
#endif
import SwiftUI
import AppKit

@main
@MainActor
struct TrunklineHostApp: App {
    @NSApplicationDelegateAdaptor(HostAppDelegate.self) private var delegate
    private var model: HostModel { delegate.model }
    @AppStorage("trunkline.appearance") private var appearance: AppAppearance = .system
    var body: some Scene {
        WindowGroup("Trunkline", id: "host") {
            HostView(model: model, client: delegate.client)
                .tint(Color("AccentColor"))
                .preferredColorScheme(appearance.colorScheme)
                .frame(minWidth: 780, minHeight: 560)
        }
        .defaultSize(width: 940, height: 720)
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
        Text(model.isConnected ? "This Mac has a connected device" : model.isRunning ? "Sharing is on" : "Sharing is off")
        Divider()
        Button("Open Trunkline") { openWindow(id: "host"); NSApp.activate(ignoringOtherApps: true) }
        if model.isConnected { Button("Disconnect device…") { model.requestDisconnectDevice() } }
        if model.isRunning { Button("Turn off sharing…") { model.requestTurnOffSharing() } }
        Divider()
        Button("Quit") { NSApplication.shared.terminate(nil) }
    }
}

struct HostView: View {
    @ObservedObject var model: HostModel
    @ObservedObject var client: MacClientModel
    enum Panel: String, CaseIterable, Identifiable {
        case sharing = "Sharing", desktop = "Desktop", power = "Power", remoteMacs = "Saved Macs", settings = "Settings"
        var id: Self { self }
        var symbol: String {
            switch self {
            case .sharing: "network"
            case .desktop: "display"
            case .power: "bolt"
            case .remoteMacs: "desktopcomputer"
            case .settings: "gearshape"
            }
        }
    }
    @State private var panel: Panel?
    private var sharingNotice: String? {
        guard let error = model.error else { return nil }
        return error.contains("credentials") ? "Saved credentials need approval" : "Sharing needs attention"
    }
    init(model: HostModel, client: MacClientModel, initialPanel: Panel = .sharing) {
        self.model = model; self.client = client
        _panel = State(initialValue: initialPanel)
    }
    var body: some View {
        NavigationSplitView {
            List(selection: $panel) {
                Section("My Mac") {
                    ForEach([Panel.sharing, .desktop, .power]) { item in
                        HStack {
                            Label(item.rawValue, systemImage: item.symbol)
                            if item == .sharing, let sharingNotice {
                                Spacer(minLength: 0)
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .help(sharingNotice)
                                    .accessibilityHidden(true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(item == .sharing ? sharingNotice ?? "" : "")
                        .tag(item)
                    }
                }
                Section("Remote Macs") {
                    Label(Panel.remoteMacs.rawValue, systemImage: Panel.remoteMacs.symbol).tag(Panel.remoteMacs)
                }
                Section {
                    Label(Panel.settings.rawValue, systemImage: Panel.settings.symbol).tag(Panel.settings)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    Image("ElephantLogo").resizable().scaledToFit().frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("This Mac").font(.callout.weight(.medium))
                        Text(model.isConnected ? "Device connected" : model.isRunning ? "Sharing on" : "Sharing off")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }.padding(16)
            }
        } detail: {
            Group {
                switch panel ?? .sharing {
                case .sharing: HostSharingView(model: model, sessions: model.terminals)
                case .remoteMacs: MacClientView(model: client, localHost: model)
                case .desktop:
                    Form {
                        sharingNoticeSection
                        DesktopSharingView(engine: model.sunshine, enabled: model.isRunning)
                        if !model.isRunning && sharingNotice == nil { Section { Button("Open Sharing") { panel = .sharing } } }
                    }.formStyle(.grouped)
                case .power:
                    Form {
                        sharingNoticeSection
                        KeepAwakeView(manager: model.keepAwake)
                        PowerControlsAuthorizationView()
                    }.formStyle(.grouped)
                case .settings: MacSettingsView()
                }
            }
            .frame(maxWidth: 840).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle((panel ?? .sharing).rawValue)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    @ViewBuilder private var sharingNoticeSection: some View {
        if let sharingNotice {
            Section {
                HStack {
                    Label {
                        Text(sharingNotice).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    Spacer(minLength: 0)
                    Button("Open Sharing") { panel = .sharing }.fixedSize()
                }
            }
        }
    }
}
