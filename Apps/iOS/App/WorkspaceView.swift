#if canImport(TrunklineCore)
import TrunklineCore
#endif
import SwiftUI

struct ConnectedTabs: View {
    @ObservedObject var model: ConnectionModel
    @State private var selection: WorkspaceSection
    @Environment(\.dynamicTypeSize) private var textSize
    @ScaledMetric(relativeTo: .subheadline) private var sidebarWidth: CGFloat = 220
    // iPad can overlay the terminal's input accessory while a hardware keyboard
    // is connected. Keep status in the scrollable sidebar, clear of that row.
    private var statusInSidebar: Bool { textSize.isAccessibilitySize || selection == .terminal }
    init(model: ConnectionModel, initialSelection: WorkspaceSection = .desktop) {
        self.model = model
        _selection = State(initialValue: initialSelection)
    }

    @ViewBuilder
    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            NavigationSplitView {
                List(selection: Binding<WorkspaceSection?>(get: { selection }, set: { if let value = $0 { selection = value } })) {
                    Section("Workspace") {
                        ForEach([WorkspaceSection.desktop, .controls, .terminal, .files]) { section in
                            NavigationLink(value: section) { Label(section.title, systemImage: section.systemImage) }
                        }
                    }
                    if statusInSidebar {
                        Section("Connected Mac") { connectionStatus }
                    }
                }
                .listStyle(.sidebar).font(.subheadline)
                .navigationTitle("Trunkline").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { MacSwitchMenu(model: model) } }
                .navigationSplitViewColumnWidth(min: 180, ideal: min(sidebarWidth, 400), max: max(280, min(sidebarWidth, 440)))
                .safeAreaInset(edge: .bottom) {
                    if !statusInSidebar { connectionStatus.padding(16) }
                }
            } detail: {
                switch selection {
                case .desktop: DesktopView(model: model)
                case .controls: ControlsView(controls: model.controls, files: model.files)
                case .terminal: SessionsView(model: model)
                case .files: FilesView(files: model.files, embedded: true)
                }
            }.navigationSplitViewStyle(.balanced)
        } else { workspaceTabs }
    }

    private var connectionStatus: some View {
        HStack(spacing: 8) {
            if !textSize.isAccessibilitySize {
                Image(systemName: "desktopcomputer").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(model.name).font(.footnote.weight(.medium))
                Text(model.useAwayAccess ? "Away connection" : "Local Wi-Fi")
                    .font(.caption).foregroundStyle(.secondary)
            }.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var workspaceTabs: some View {
        TabView(selection: $selection) {
            DesktopView(model: model)
                .tabItem { Label(WorkspaceSection.desktop.title, systemImage: WorkspaceSection.desktop.systemImage) }
                .tag(WorkspaceSection.desktop)
            ControlsView(controls: model.controls, files: model.files)
                .tabItem { Label("Controls", systemImage: "slider.horizontal.3") }.tag(WorkspaceSection.controls)
            SessionsView(model: model)
                .tabItem { Label(WorkspaceSection.terminal.title, systemImage: WorkspaceSection.terminal.systemImage) }
                .tag(WorkspaceSection.terminal)
            FilesView(files: model.files, embedded: true)
                .tabItem { Label("Files", systemImage: "folder") }.tag(WorkspaceSection.files)
        }
        .tint(Color("AccentColor"))
        .environment(\.defaultMinListRowHeight, 44)
    }
}

