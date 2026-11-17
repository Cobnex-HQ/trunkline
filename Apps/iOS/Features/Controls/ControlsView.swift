#if canImport(TrunklineCore)
import TrunklineCore
#endif
import SwiftUI

struct ControlsView: View {
    @ObservedObject var controls: ClientControls
    @State private var volume = 0.5
    @State private var editingVolume = false
    @State private var search = ""
    @State private var confirmation: MacControlAction?
    @State private var confirmationTitle = ""
    @State private var clipboard = false
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .caption) private var quickActionHeight: CGFloat = 52
    @ObservedObject var files: ClientFiles
    var dismissible = false
    @Environment(\.dismiss) private var dismiss
    private static let quickActionControls: [SystemControl] = [.spotlight, .missionControl, .showDesktop, .switchApp, .appWindows, .screenshot]
    private var appQuery: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            List {
                if let state = controls.snapshot {
                    let matchingApps = state.apps.filter { appQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(appQuery) }
                    if appQuery.isEmpty {
                        if !state.accessibility {
                            Section { Label("Enable Accessibility on the Mac for keyboard and window controls.", systemImage: "hand.raised") }
                        }
                        Section("Quick actions") {
                            if textSize.isAccessibilitySize {
                                ForEach(Self.quickActionControls) { action in
                                    Button { controls.perform(.system(action)) } label: {
                                        Label(action.title, systemImage: action.symbol)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(minHeight: 44)
                                    }.disabled(!state.accessibility)
                                }
                            } else {
                                ViewThatFits(in: .horizontal) {
                                    quickActions(columns: 6, enabled: state.accessibility)
                                    quickActions(columns: 3, enabled: state.accessibility)
                                    quickActions(columns: 2, enabled: state.accessibility)
                                    quickActions(columns: 1, enabled: state.accessibility)
                                }.padding(.vertical, 8)
                            }
                        }
                    }
                    Section("Apps") {
                        if !appQuery.isEmpty && matchingApps.isEmpty {
                            ContentUnavailableView.search(text: appQuery)
                        }
                        ForEach(matchingApps) { app in
                            HStack(spacing: 12) {
                                Button { controls.perform(.activateApp(app.pid)) } label: {
                                    ApplicationControlLabel(name: app.name, status: app.active ? "Active" : nil, active: app.active)
                                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .accessibilityLabel("Bring \(app.name) forward")
                                    .accessibilityValue(app.active ? "Active" : "")
                                Menu {
                                    Button("Bring forward") { controls.perform(.activateApp(app.pid)) }
                                    Button("Quit", role: .destructive) { confirm(.quitApp(app.pid), title: "Quit \(app.name)?") }
                                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Actions for \(app.name)")
                            }
                        }
                        NavigationLink {
                            AppLauncherView(controls: controls)
                        } label: {
                            Label("Open app", systemImage: "plus.app").frame(minHeight: 44)
                        }
                    }
                    if appQuery.isEmpty {
                        Section(state.windowScope == nil ? "Windows · \(state.frontmostApp)" : "Windows") {
                            if state.windowScope != nil {
                                Picker("App", selection: Binding<Int32?>(get: { controls.selectedWindowAppPID }, set: { controls.selectWindowApplication($0) })) {
                                    Text("Active app: \(state.frontmostApp)").tag(Int32?.none)
                                    ForEach(state.apps) { app in Text(app.name).tag(Optional(app.pid)) }
                                    if let pid = controls.selectedWindowAppPID, !state.apps.contains(where: { $0.pid == pid }) {
                                        Text("Closed app").tag(Optional(pid))
                                    }
                                }.disabled(!state.accessibility).accessibilityLabel("Windows from app")
                            }
                            if controls.hasCurrentWindowList {
                                if let error = state.windowScope?.error {
                                    Text(error).foregroundStyle(.secondary)
                                    Button("Refresh windows", systemImage: "arrow.clockwise") { controls.refresh() }
                                        .disabled(controls.isRefreshing)
                                } else if state.windows.isEmpty { Text("No windows available").foregroundStyle(.secondary) }
                                ForEach(state.windows) { window in
                                    Menu {
                                        ForEach(WindowControl.allCases, id: \.self) { action in
                                            Button(action.title) { controls.perform(.window(window.id, action)) }
                                        }
                                        if window.canMoveToDisplay == true, state.displays.count > 1 {
                                            Menu("Move to Display", systemImage: "display.2") {
                                                ForEach(state.displays) { display in
                                                    Button(display.name) { controls.perform(.moveWindow(window.id, displayID: display.id)) }
                                                }
                                            }
                                        }
                                    } label: {
                                        Label(window.title, systemImage: window.minimized ? "minus.rectangle" : "macwindow")
                                            .foregroundStyle(.primary).frame(minHeight: 44)
                                    }
                                }
                                if let page = state.windowPage, page.nextCursor != nil {
                                    Button { controls.loadMoreWindows() } label: {
                                        HStack {
                                            Text("Load more windows")
                                            Spacer()
                                            Text("\(state.windows.count) of \(page.totalCount)")
                                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                        }.frame(minHeight: 44)
                                    }.disabled(controls.isRefreshing)
                                }
                            } else if controls.isRefreshing {
                                HStack(spacing: 12) { ProgressView(); Text("Loading windows…").foregroundStyle(.secondary) }
                            } else {
                                Button("Load windows", systemImage: "arrow.clockwise") { controls.refresh() }
                            }
                        }
                        Section("Sound") {
                            if let outputs = state.audioOutputs {
                                if outputs.isEmpty {
                                    Text("No audio outputs connected").foregroundStyle(.secondary)
                                } else {
                                    soundOutputPicker(outputs)
                                }
                            }
                            if state.volume != nil {
                                HStack {
                                    if let muted = state.muted {
                                        Button { controls.perform(.mute(!muted)) } label: {
                                            Image(systemName: muted ? "speaker.slash.fill" : "speaker.fill").frame(width: 44, height: 44)
                                        }.accessibilityLabel(muted ? "Unmute" : "Mute").accessibilityValue(muted ? "Muted" : "Sound on")
                                    } else { Image(systemName: "speaker.fill") }
                                    Slider(value: $volume, in: 0...1) { editing in
                                        editingVolume = editing
                                        if !editing { controls.perform(.volume(volume)) }
                                    }.accessibilityLabel("Mac volume")
                                    Image(systemName: "speaker.wave.3.fill")
                                }.frame(minHeight: 44)
                            } else { Text("Volume is controlled by the output device.").foregroundStyle(.secondary) }
                            HStack {
                                media(.previousTrack); Spacer(); media(.playPause); Spacer(); media(.nextTrack)
                            }.padding(.horizontal)
                        }
                        Section("Displays") {
                            ForEach(state.displays) { display in
                                LabeledContent(display.name, value: "\(display.width) × \(display.height)")
                            }
                            HStack { media(.brightnessDown); Spacer(); media(.brightnessUp) }
                        }
                        Section("Mac") {
                            if let awake = state.keepAwake {
                                Picker("Keep awake", selection: Binding(get: { awake.mode }, set: { controls.perform(.keepAwake($0)) })) {
                                    Text("Automatic").tag(AwakeMode.off)
                                    Text("Mac").tag(AwakeMode.system)
                                    Text("Mac and display").tag(AwakeMode.systemAndDisplay)
                                    if awake.mode == .lidClosed { Text("Closed lid · set on Mac").tag(AwakeMode.lidClosed) }
                                }.disabled(controls.pending != nil || awake.requiresLocalChange)
                                Text(awake.requiresLocalChange
                                     ? "Change closed-lid or recovery settings on the Mac first."
                                     : "Active connections keep the Mac and display awake. Extra keep-awake stays on until you change it or quit the Mac app.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Button("Clipboard", systemImage: "clipboard") { files.send?(.requestClipboard); clipboard = true }
                            Menu {
                                Button("Lock Mac", systemImage: "lock") { confirm(.system(.lock), title: "Lock your Mac?") }
                                Button("Sleep Mac", systemImage: "moon") { confirm(.system(.sleep), title: "Put your Mac to sleep?") }
                                if let power = state.power, !power.availableActions.isEmpty {
                                    Divider()
                                    ForEach(power.availableActions) { action in
                                        Button(action.title, systemImage: action.symbol, role: .destructive) {
                                            confirm(.power(action), title: action.title + "?")
                                        }
                                    }
                                }
                            } label: { Label("Power", systemImage: "power").frame(minHeight: 44) }
                            if state.power?.authorizationRequired == true {
                                Text("Allow power controls in Trunkline’s Power settings on the Mac to restart, shut down or log out.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else if controls.refreshError == nil {
                    Section { HStack(spacing: 12) { GlacierLoadingIndicator(); Text("Loading controls…") } }
                }
                if let error = controls.refreshError {
                    Section {
                        Label(error, systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
                        Button(controls.isRefreshing ? "Refreshing…" : "Try again") { controls.refresh() }
                            .disabled(controls.isRefreshing)
                    }
                }
                if let error = controls.error { Section { Text(error).foregroundStyle(.orange); Button("Refresh") { controls.error = nil; controls.refresh() } } }
            }
            .disabled(controls.pending != nil)
            .nativeWorkspaceStyle()
            .frame(maxWidth: 780).frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Controls")
            .searchable(text: $search, prompt: "Find a running app")
            .refreshable { controls.refresh() }
            .toolbar {
                if dismissible { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                ToolbarItem(placement: .topBarTrailing) {
                    if controls.pending != nil || controls.isRefreshing { ProgressView() }
                    else { Button("Refresh", systemImage: "arrow.clockwise") { controls.refresh() } }
                }
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    controls.refresh(automatically: true)
                    do { try await Task.sleep(for: .seconds(5)) } catch { break }
                }
            }
            .onChange(of: controls.snapshot?.volume, initial: true) { _, value in if let value, !editingVolume { volume = value } }
            .alert(confirmationTitle, isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), presenting: confirmation) { action in
                Button(confirmationLabel(action), role: .destructive) { controls.perform(action, confirmed: true); confirmation = nil }
                Button("Cancel", role: .cancel) { confirmation = nil }
            } message: { action in
                Text(confirmationMessage(action))
            }
            .sheet(isPresented: $clipboard) { ClipboardView(files: files) }
        }
    }
    private func quickActions(columns: Int, enabled: Bool) -> some View {
        let minimum: CGFloat = 92
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(Self.quickActionControls) { action in
                Button { controls.perform(.system(action)) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: action.symbol).font(.body)
                        Text(action.title).font(.caption).multilineTextAlignment(.center).lineLimit(2, reservesSpace: true)
                    }.frame(maxWidth: .infinity).frame(minHeight: quickActionHeight)
                }.buttonStyle(.bordered).tint(Color("AccentColor")).disabled(!enabled)
            }
        }.frame(minWidth: minimum * CGFloat(columns) + 8 * CGFloat(columns - 1))
    }
    @ViewBuilder private func soundOutputPicker(_ outputs: [MacAudioOutput]) -> some View {
        let selectedName = outputs.first(where: \.selected)?.name ?? "Select output"
        let picker = Picker("Output", selection: Binding(
            get: { outputs.first(where: \.selected)?.id ?? "" },
            set: { controls.perform(.audioOutput($0)) }
        )) {
            if !outputs.contains(where: \.selected) { Text("Select output").tag("") }
            ForEach(outputs) { output in Text(output.name).tag(output.id) }
        }
        if textSize.isAccessibilitySize {
            Menu { picker } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Output").font(.caption).foregroundStyle(.secondary)
                    Text(selectedName).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.accessibilityLabel("Mac sound output").accessibilityValue(selectedName)
        } else {
            picker.accessibilityLabel("Mac sound output").accessibilityValue(selectedName)
        }
    }
    private func confirm(_ action: MacControlAction, title: String) { confirmationTitle = title; confirmation = action }
    private func confirmationLabel(_ action: MacControlAction) -> String {
        switch action {
        case let .power(action): action.title
        case let .system(action): action.title
        case .quitApp: "Quit App"
        default: "Continue"
        }
    }
    private func confirmationMessage(_ action: MacControlAction) -> String {
        switch action {
        case let .power(action): action.consequence
        case .system(.sleep): "The connection will close. You may need to wake the Mac locally."
        case .system(.lock): "You’ll need your Mac login password to unlock the desktop."
        default: "Unsaved work may need attention on the desktop."
        }
    }
    private func media(_ action: SystemControl) -> some View {
        Button { controls.perform(.system(action)) } label: {
            Label(action.title, systemImage: action.symbol).labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
        }.disabled(controls.snapshot?.accessibility != true)
    }
}

private struct AppLauncherView: View {
    @ObservedObject var controls: ClientControls
    @State private var search = ""
    @State private var selectedBundle: String?
    @Environment(\.dismiss) private var dismiss

    private var applications: [MacInstalledApplication] {
        (controls.snapshot?.installedApps ?? []).filter {
            search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        List {
            if controls.snapshot?.loadingApps == true {
                HStack(spacing: 12) { GlacierLoadingIndicator(); Text("Finding apps…") }
            } else if controls.snapshot?.installedApps == nil {
                ContentUnavailableView("App list unavailable", systemImage: "app.dashed",
                    description: Text("Update Trunkline on your Mac to browse installed apps."))
            } else if applications.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                ForEach(applications) { app in
                    Button {
                        selectedBundle = app.bundleID
                        controls.perform(.launchApp(app.bundleID))
                    } label: {
                        HStack(spacing: 12) {
                            ApplicationControlLabel(name: app.name,
                                status: controls.snapshot?.apps.contains(where: { $0.bundleID == app.bundleID }) == true ? "Running" : nil)
                            if selectedBundle == app.bundleID && controls.pending != nil { ProgressView() }
                        }.frame(minHeight: 44)
                    }.disabled(controls.pending != nil)
                }
            }
            if let error = controls.error { Section { Text(error).foregroundStyle(.orange) } }
        }
        .nativeWorkspaceStyle()
        .frame(maxWidth: 780).frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Open app")
        .searchable(text: $search, prompt: "Find an app")
        .onChange(of: controls.pending) { previous, current in
            if previous != nil, current == nil, selectedBundle != nil, controls.error == nil { dismiss() }
        }
    }
}

private struct ApplicationControlLabel: View {
    let name: String
    let status: String?
    var active = false
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        HStack(spacing: 12) {
            if !textSize.isAccessibilitySize {
                Image(systemName: active ? "app.badge.fill" : "app")
                    .foregroundStyle(active ? Color.accentColor : .secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.subheadline.weight(.medium)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                if textSize.isAccessibilitySize, let status {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if !textSize.isAccessibilitySize, let status {
                Text(status).font(.caption).foregroundStyle(.secondary).fixedSize()
            }
        }
    }
}
