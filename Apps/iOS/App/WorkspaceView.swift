#if canImport(TrunklineCore)
import TrunklineCore
#endif
import SwiftUI

struct ConnectedTabs: View {
    @ObservedObject var model: ConnectionModel
    @State private var selection: WorkspaceSection
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var columns: NavigationSplitViewVisibility = .automatic
    @State private var workspaceWidth: CGFloat = 0
    init(model: ConnectionModel, initialSelection: WorkspaceSection = .desktop) {
        self.model = model
        _selection = State(initialValue: initialSelection)
    }

    @ViewBuilder
    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            NavigationSplitView(columnVisibility: $columns) {
                List(selection: Binding<WorkspaceSection?>(get: { selection }, set: { if let value = $0 { selection = value } })) {
                    TrunklineSection("Workspace") {
                        ForEach([WorkspaceSection.desktop, .controls, .terminal, .files]) { section in
                            NavigationLink(value: section) {
                                Label(section.title, systemImage: section.systemImage)
                            }
                        }
                    }
                    TrunklineSection("Connected Mac") {
                        connectionStatus
                        MacSwitchMenu(model: model)
                    }
                }
                .listStyle(.sidebar).font(.subheadline)
                .scrollContentBackground(.hidden)
                .background(Color.workspaceBackground)
                .navigationTitle("Trunkline").navigationBarTitleDisplayMode(.inline)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
            } detail: {
                switch selection {
                case .desktop: DesktopView(model: model)
                case .controls: ControlsView(controls: model.controls, files: model.files)
                case .terminal: SessionsView(model: model)
                case .files: FilesView(files: model.files, embedded: true)
                }
            }
            .navigationSplitViewStyle(.balanced)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                workspaceWidth = width
                fitColumns()
            }
            .onChange(of: selection) { _, _ in fitColumns() }
            .onChange(of: model.selectedTerminalID) { _, _ in fitColumns() }
        } else { workspaceTabs }
    }

    // Keep one navigation hierarchy during rotation. Only column visibility changes,
    // so terminal selection, keyboard focus and drafts remain attached to their views.
    private func fitColumns() {
        let editingTerminal = selection == .terminal && model.selectedTerminalID != nil
        columns = workspaceWidth >= 900 && !editingTerminal ? .all : .detailOnly
    }

    private var connectionStatus: some View {
        HStack(spacing: 8) {
            if !textSize.isAccessibilitySize {
                Image(systemName: "desktopcomputer").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
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

