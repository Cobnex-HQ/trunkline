#if canImport(TrunklineCore)
import TrunklineCore
#endif
import SwiftUI
import CryptoKit

@MainActor
final class DesktopSession: ObservableObject {
    struct Application: Identifiable { let id: String; let name: String }
    @Published var apps: [Application] = []
    @Published var busy = false
    @Published var paired = false
    @Published var hostReady = false
    @Published var pin: String?
    @Published var error: String?
    @Published var stream: StreamConfiguration?
    @Published var presenting = false
    @Published var profile: StreamProfile = .responsive { didSet { persist(\.profile, profile) } }
    @Published var inputMode: DesktopInputMode = .directTouch { didSet { persist(\.inputMode, inputMode) } }
    @Published var pacing: StreamPacingMode = .lowLatency { didSet { persist(\.pacing, pacing) } }
    @Published var stats = false { didSet { persist(\.statistics, stats) } }
    @Published var adaptiveQuality = true { didSet { persist(\.adaptiveQuality, adaptiveQuality) } }
    private(set) var engine: TrunklineStream
    private let engineFactory: () -> TrunklineStream
    private var preferenceID: String?
    private var preferences = MacPreferencesStore()
    private let discoveryTimeout: Duration
    private let pairingTimeout: Duration
    private var deadline: Task<Void, Never>?
    private var operationID: UUID?
    private var address = ""
    private var certificateKey = ""
    private var closed = false
    private var openRequested = false
    private var approvePairing: ((DesktopPairRequest) -> Void)?
    var display = DesktopDisplay.fallback
    init(discoveryTimeout: Duration = .seconds(15), pairingTimeout: Duration = .seconds(30),
         engineFactory: @escaping () -> TrunklineStream = { TrunklineStream() }) {
        self.discoveryTimeout = discoveryTimeout; self.pairingTimeout = pairingTimeout
        self.engineFactory = engineFactory; self.engine = engineFactory()
    }
    func configurePreferences(macID: String, store: MacPreferencesStore) {
        preferenceID = nil
        preferences = store
        let saved = store.load(macID)
        profile = saved.profile; inputMode = saved.inputMode; pacing = saved.pacing
        stats = saved.statistics; adaptiveQuality = saved.adaptiveQuality
        preferenceID = macID
    }
    private func persist<Value>(_ key: WritableKeyPath<MacPreferences, Value>, _ value: Value) {
        guard let preferenceID else { return }
        preferences.update(preferenceID) { $0[keyPath: key] = value }
    }
    func open(pairingLink: String, approvePairing: @escaping (DesktopPairRequest) -> Void) {
        guard address.isEmpty else { return }
        do {
            let pairing = try PairingDetails.parse(pairingLink)
            address = pairing.host.contains(":") ? "[\(pairing.host)]:47989" : "\(pairing.host):47989"
            certificateKey = DesktopTrustKey.current(pairing)
            if SecretStore.read(certificateKey) == nil, let certificate = SecretStore.read(DesktopTrustKey.legacy(pairing)) {
                try SecretStore.write(certificate, key: certificateKey)
            }
            self.approvePairing = approvePairing
            bindEngineCallbacks()
            refresh()
        } catch { self.error = error.localizedDescription }
    }
    private func bindEngineCallbacks() {
        let engine = self.engine
        engine.pairingCode = { [weak self, weak engine] code in
            guard let self, let engine, self.engine === engine, !self.closed else { return }
            self.pin = code
            do { self.approvePairing?(try DesktopPairRequest(pin: code, token: engine.pairingToken)) }
            catch { self.receivePairingFailure(error.localizedDescription, token: engine.pairingToken) }
        }
        engine.paired = { [weak self, weak engine] certificate in
            guard let self, let engine, self.engine === engine, !self.closed else { return }
            self.stopDeadline()
            self.pin = nil; self.busy = false
            do { try SecretStore.write(certificate, key: self.certificateKey); self.refresh() }
            catch { self.openRequested = false; self.error = error.localizedDescription }
        }
        engine.failed = { [weak self, weak engine] message in
            guard let self, let engine, self.engine === engine, !self.closed else { return }
            self.resetPreparation(error: message)
        }
    }
    func refresh() {
        guard !busy, !closed, !presenting, !address.isEmpty else { return }; busy = true; error = nil
        let id = armDeadline(discoveryTimeout, message: "Desktop didn’t respond. Check that Desktop is running on your Mac, then retry.")
        let engine = self.engine
        let certificate = SecretStore.read(certificateKey)
        paired = certificate != nil
        engine.loadHost(address, certificate: certificate) { [weak self, weak engine] applications, error in
            Task { @MainActor in
                guard let self, let engine, !self.closed, self.engine === engine, self.operationID == id else { return }
                self.stopDeadline(); self.busy = false
                if let error { self.hostReady = false; self.error = error; self.openRequested = false; return }
                #if DEBUG
                if self.address.hasPrefix("127.0.0.1:") { print("TRUNKLINE_REMOTE desktop_host_ready"); fflush(stdout) }
                #endif
                self.hostReady = true
                self.apps = (applications ?? []).compactMap { item in
                    guard let id = item["id"], let name = item["name"] else { return nil }
                    return Application(id: id, name: name)
                }
                if self.openRequested { self.openDesktop() }
            }
        }
    }

    func openDesktop() {
        guard !busy, !closed else { return }
        openRequested = true
        if !hostReady { refresh() }
        else if !paired { pair() }
        else if let desktop = apps.first(where: { $0.name == "Desktop" }) {
            openRequested = false; launch(desktop)
        } else { openRequested = false; error = "No Desktop is available. Restart desktop in the Mac app, then retry." }
    }
    func pair() {
        guard !busy, !closed, hostReady else { return }; busy = true; error = nil
        _ = armDeadline(pairingTimeout, message: "Desktop pairing timed out. Check the Mac connection, then retry.")
        engine.pair()
    }
    func receivePairingFailure(_ message: String, token: String?) {
        guard !closed, pin != nil, token == engine.pairingToken else { return }
        resetPreparation(error: message)
    }
    func cancelPreparation() { guard busy, !presenting else { return }; resetPreparation(error: nil) }
    private func resetPreparation(error: String?) {
        stopDeadline(); engine.cancel(); engine = engineFactory(); bindEngineCallbacks()
        busy = false; pin = nil; hostReady = false; openRequested = false; apps = []
        self.error = error
    }
    @discardableResult private func armDeadline(_ duration: Duration, message: String) -> UUID {
        stopDeadline()
        let id = UUID(); operationID = id
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: duration) } catch { return }
            guard let self, self.operationID == id, !self.closed else { return }
            self.resetPreparation(error: message)
        }
        return id
    }
    private func stopDeadline() { deadline?.cancel(); deadline = nil; operationID = nil }
    func forget() { guard !busy else { return }; SecretStore.delete(certificateKey); paired = false; apps = []; refresh() }
    func launch(_ application: Application) {
        guard paired, !busy else { return }
        guard TrunklineDesktopStreamAvailable() else {
            error = "A desktop is open in another window. Close that desktop before opening this one."
            return
        }
        let geometry = DesktopStreamGeometry.size(
            maximumWidth: profile.maximumWidth,
            displayWidth: display.width,
            displayHeight: display.height
        )
        let fps = StreamFrameRatePolicy.targetFramesPerSecond(
            for: profile,
            preStreamDisplayMaximum: UIScreen.main.maximumFramesPerSecond
        )
        guard let config = engine.configuration(forApp: application.id, title: application.name,
            width: Int32(geometry.width), height: Int32(geometry.height), fps: Int32(fps), bitrate: Int32(profile.bitrate / 1000), directTouch: inputMode.usesAbsolutePointer, framePacing: pacing.usesFramePacing, stats: stats) else {
            error = "Refresh your desktop connection before starting the desktop."; return
        }
        stream = config; presenting = true
    }
    func close() {
        closed = true; stopDeadline(); presenting = false; stream = nil; approvePairing = nil; engine.cancel()
        busy = false; pin = nil; hostReady = false; apps = []; openRequested = false
    }
}

struct DesktopView: View {
    @ObservedObject var model: ConnectionModel
    @StateObject private var desktop = DesktopSession()
    @ObservedObject private var controls: ClientControls
    init(model: ConnectionModel) { self.model = model; self.controls = model.controls }
    @Environment(\.scenePhase) private var scenePhase
    @State private var settings = false
    @State private var diagnostics = false
    @State private var disconnect = false
    var body: some View {
        NavigationStack {
            List {
                TrunklineSection {
                    HStack(spacing: 12) {
                        Image(systemName: "desktopcomputer").font(.title2).foregroundStyle(.secondary)
                            .frame(width: 36).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.name).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 5) {
                                Circle().fill(desktop.hostReady ? Color.green : Color.orange).frame(width: 5, height: 5)
                                Text(desktop.hostReady ? "Ready" : desktop.busy ? "Preparing" : desktop.error == nil ? "Not connected" : "Unavailable")
                                Text("·").foregroundStyle(.tertiary)
                                Text(model.useAwayAccess ? "Away" : "Local Wi-Fi")
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        ZStack(alignment: .trailing) {
                            Text(model.roundTripMS.map { "\($0) ms" } ?? "")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .opacity(desktop.busy ? 0 : 1)
                                .accessibilityHidden(desktop.busy)
                            Button("Cancel", role: .cancel) { desktop.cancelPreparation() }
                                .buttonStyle(.borderless)
                                .opacity(desktop.busy ? 1 : 0)
                                .allowsHitTesting(desktop.busy)
                                .accessibilityHidden(!desktop.busy)
                        }.frame(width: 64, height: 44)
                    }.padding(.vertical, 4)
                    Button {
                        desktop.display = controls.snapshot?.desktopDisplays?.selectedDisplay?.geometry ?? model.desktopDisplay
                        desktop.openDesktop()
                    } label: {
                        Label("Open desktop", systemImage: "arrow.up.right.square")
                            .trunklineActionLabel()
                            .padding(.trailing, 28)
                            .overlay(alignment: .trailing) {
                                ProgressView().controlSize(.small).tint(.white)
                                    .frame(width: 20)
                                    .opacity(desktop.busy ? 1 : 0)
                                    .accessibilityHidden(true)
                            }
                    }.trunklineActionStyle(prominent: true).disabled(desktop.busy || controls.pending != nil || controls.snapshot?.desktopDisplays?.switching == true)
                }
                if let error = desktop.error {
                    TrunklineSection { Text(error).foregroundStyle(.orange); Button("Retry") { desktop.openDesktop() }.disabled(desktop.busy) }
                }
                if controls.snapshot?.desktopDisplays?.isAvailable == true {
                    TrunklineSection("Display") { DesktopDisplayMenu(controls: controls) }
                }
                TrunklineSection {
                    Picker("Input", selection: $desktop.inputMode) { ForEach(DesktopInputMode.allCases) { Text($0.title).tag($0) } }
                    Toggle("Adapt to network", isOn: $desktop.adaptiveQuality)
                    Picker("Quality limit", selection: $desktop.profile) { ForEach(StreamProfile.allCases) { Text($0.title).tag($0) } }
                    LabeledContent("Connection", value: model.useAwayAccess ? "Direct · Away" : "Local Wi-Fi")
                } header: { Text("Stream") } footer: {
                    Text("Pinch to zoom. Use two fingers to pan when zoomed. Adaptive quality adjusts bandwidth up to your quality limit when the Mac supports it.")
                }
                TrunklineSection("Appearance") { AppearancePicker() }
            }
            .nativeWorkspaceStyle()
            .frame(maxWidth: 780).frame(maxWidth: .infinity)
            .background(Color.workspaceBackground)
            .navigationTitle("Desktop")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { MacSwitchMenu(model: model) }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Stream settings", systemImage: "slider.horizontal.3") { settings = true }
                        Button("Connection details", systemImage: "network") { diagnostics = true }
                        Button("Refresh", systemImage: "arrow.clockwise") { desktop.refresh() }
                        Button("Disconnect", systemImage: "power", role: .destructive) { disconnect = true }
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Desktop options")
                }
            }
            .task {
                if let id = model.selectedMacID { desktop.configurePreferences(macID: id, store: model.preferences) }
                model.onDesktopError = { [weak desktop] message, token in desktop?.receivePairingFailure(message, token: token) }
                desktop.display = model.desktopDisplay
                desktop.open(pairingLink: model.sessionPairingLink.isEmpty ? model.pairingText : model.sessionPairingLink) { model.send(.pairDesktop($0)) }
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    if !desktop.presenting { controls.refresh(automatically: true) }
                    do { try await Task.sleep(for: .seconds(5)) } catch { break }
                }
            }
            .onChange(of: controls.snapshot?.desktopDisplays) { _, selection in
                desktop.display = selection?.selectedDisplay?.geometry ?? model.desktopDisplay
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active && !desktop.presenting && desktop.pin == nil { desktop.refresh() } }
            .onChange(of: model.phase) { _, phase in if phase != .connected { desktop.close() } }
            .onChange(of: model.desktopDisplay) { _, display in desktop.display = display }
            .confirmationDialog("Disconnect from your Mac?", isPresented: $disconnect, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) { model.disconnect() }
            }
            .sheet(isPresented: $diagnostics) {
                ConnectionDiagnosticsView(diagnostic: model.diagnostic, snapshot: controls.snapshot, refresh: { controls.refresh() })
            }
            .sheet(isPresented: $settings) {
                NavigationStack {
                    Form {
                        TrunklineSection {
                            Picker("Motion", selection: $desktop.pacing) { ForEach(StreamPacingMode.allCases) { Text($0.title).tag($0) } }
                            Toggle("Statistics", isOn: $desktop.stats)
                        } header: { Text("Playback") } footer: { Text(desktop.inputMode.detail) }
                    }
                    .nativeWorkspaceStyle()
                    .navigationTitle("Stream settings")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { settings = false } } }
                }.presentationDetents([.medium, .large])
            }
            .fullScreenCover(isPresented: $desktop.presenting, onDismiss: { desktop.stream = nil }) {
                if let config = desktop.stream { DesktopScreen(engine: desktop.engine, config: config, model: model, adaptive: desktop.adaptiveQuality) { desktop.presenting = false } }
            }
        }
    }
}

private struct DesktopSurface: UIViewControllerRepresentable {
    let engine: TrunklineStream
    let config: StreamConfiguration
    let close: () -> Void
    @Binding var controller: UIViewController?
    func makeUIViewController(context: Context) -> UIViewController {
        let view = engine.streamController(withConfig: config, close: close) { [weak engine] name in
            guard let engine, let action = DesktopWorkspaceAction(rawValue: name) else { return }
            action.perform(on: engine)
        }
        DispatchQueue.main.async { controller = view }
        return view
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: ()) {
        uiViewController.willMove(toParent: nil)
    }
}

private struct DesktopScreen: View {
    let engine: TrunklineStream
    let config: StreamConfiguration
    @ObservedObject var model: ConnectionModel
    var adaptive = true
    let close: () -> Void
    @StateObject private var quality = AdaptiveDesktopQuality()
    @SwiftUI.State private var showControls = false
    @SwiftUI.State private var showGestures = false
    @Environment(\.scenePhase) private var scenePhase
    @SwiftUI.State private var toolbarVisible = true
    @SwiftUI.State private var controller: UIViewController?
    @SwiftUI.State private var paste = false
    @SwiftUI.State private var text = ""
    @SwiftUI.State private var pendingMonitorID: String?
    @SwiftUI.State private var monitorSwitching = false
    @SwiftUI.State private var externalDisplay = false
    var body: some View {
        VStack(spacing: 0) {
            desktopSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
                .allowsHitTesting(pendingMonitorID == nil && !monitorSwitching)
                .overlay {
                    if pendingMonitorID != nil || monitorSwitching {
                        ProgressView("Switching display…").padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            if toolbarVisible {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        leadingTools
                        tool("Mission Control", "rectangle.3.group") { DesktopWorkspaceAction.missionControl.perform(on: engine) }
                        workspaceMenu
                        Divider().frame(height: 24)
                        zoomTools
                        Divider().frame(height: 24)
                        trailingTools
                    }.fixedSize(horizontal: true, vertical: false)
                    HStack(spacing: 4) {
                        leadingTools
                        workspaceMenu
                        DesktopDisplayMenu(controls: model.controls, compact: true) { pendingMonitorID = $0 }
                        Menu {
                            zoomCommands
                            Divider()
                            shortcutCommands
                            Divider()
                            Button("Mac controls", systemImage: "slider.horizontal.3") { showControls = true }
                            Button("Hide toolbar", systemImage: "chevron.down") { toolbarVisible = false }
                        } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                            .accessibilityLabel("More desktop controls")
                    }
                }
                .frame(maxWidth: .infinity).padding(.horizontal, 8).padding(.vertical, 4)
                .background(.regularMaterial)
            } else {
                Button { toolbarVisible = true } label: { Label("Controls", systemImage: "chevron.up").frame(minHeight: 44) }
                    .frame(maxWidth: .infinity).background(.regularMaterial)
            }
        }
        .background(.black)
        #if DEBUG && targetEnvironment(simulator)
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--ui-review"),
               ProcessInfo.processInfo.environment["TRUNKLINE_REVIEW_EXTERNAL"] == "1" { externalDisplay = true }
        }
        #endif
        .background {
            if #available(iOS 27.0, *) {
                ExternalDisplayPresentation(source: controller, enabled: externalDisplay && scenePhase == .active)
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showControls) {
            ControlsView(controls: model.controls, files: model.files, dismissible: true)
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                model.controls.refresh(automatically: true)
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
            }
        }
        .task(id: scenePhase) {
            guard adaptive, scenePhase == .active else { return }
            while !Task.isCancelled {
                if let sample = TrunklineDesktopNetworkSample(), let time = sample["time"], let loss = sample["loss"] {
                    quality.observe(controls: model.controls, ceiling: Int(config.bitRate),
                                    loss: loss.doubleValue, sampleTime: time.doubleValue, now: CACurrentMediaTime())
                }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
        .onReceive(model.controls.$lastResult) { quality.receive($0) }
        .sheet(isPresented: $showGestures) { gestureHelp }
        .onChange(of: controller) { _, _ in updateDisplayGeometry(model.controls.snapshot) }
        .onReceive(model.controls.$snapshot) { snapshot in updateDisplayGeometry(snapshot) }
        .onReceive(model.controls.$error) { error in
            if error != nil { pendingMonitorID = nil }
        }
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $paste) {
            DesktopTextSheet(text: $text) {
                text = ""
                paste = false
            } send: {
                engine.sendText(text)
                text = ""
                paste = false
            }
        }
    }
    @ViewBuilder private var desktopSurface: some View {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-review") {
            ExternalDisplayReviewSurface(controller: $controller)
        } else {
            DesktopSurface(engine: engine, config: config, close: close, controller: $controller)
        }
        #else
        DesktopSurface(engine: engine, config: config, close: close, controller: $controller)
        #endif
    }
    private func updateDisplayGeometry(_ snapshot: MacControlSnapshot?) {
        let selection = snapshot?.desktopDisplays
        monitorSwitching = selection?.switching == true
        guard !monitorSwitching, let controller else { return }
        if let pending = pendingMonitorID {
            guard selection?.activeID == pending || selection?.error != nil else { return }
            pendingMonitorID = nil
        }
        let display = selection?.displays.first(where: { $0.id == selection?.activeID })?.geometry
            ?? selection?.selectedDisplay?.geometry ?? model.desktopDisplay
        engine.updateDisplay(in: controller, width: Int32(display.width), height: Int32(display.height))
    }
    private var leadingTools: some View {
        Group {
            tool("Close", "xmark", action: close)
            tool("Keyboard", "keyboard") { if let controller { engine.showKeyboard(in: controller) } }
        }
    }
    private var zoomTools: some View {
        Group {
            tool("Zoom out", "minus.magnifyingglass") { zoom(1 / 1.4) }
            tool("Fit", "arrow.down.right.and.arrow.up.left") { zoom(0) }
            tool("Zoom in", "plus.magnifyingglass") { zoom(1.4) }
        }
    }
    private var zoomCommands: some View {
        Group {
            Button("Zoom in", systemImage: "plus.magnifyingglass") { zoom(1.4) }
            Button("Zoom out", systemImage: "minus.magnifyingglass") { zoom(1 / 1.4) }
            Button("Fit desktop", systemImage: "arrow.down.right.and.arrow.up.left") { zoom(0) }
        }
    }
    private func zoom(_ factor: CGFloat) {
        guard let controller else { return }
        if factor == 0 { engine.resetZoom(in: controller) }
        else { engine.changeZoom(in: controller, factor: factor) }
    }
    private var workspaceMenu: some View {
        Menu {
            ForEach(DesktopWorkspaceAction.allCases) { action in
                Button(action.title, systemImage: action.symbol) { action.perform(on: engine) }
            }
            Divider()
            Button("Gestures & displays", systemImage: "hand.draw") { showGestures = true }
            if #available(iOS 27.0, *), UIDevice.current.userInterfaceIdiom == .pad {
                Toggle("Use external display", systemImage: "display.2", isOn: $externalDisplay)
            }
        } label: { Image(systemName: "rectangle.stack").frame(width: 44, height: 44) }
            .accessibilityLabel("Spaces and windows")
    }
    private var gestureHelp: some View {
        NavigationStack {
            List {
                TrunklineSection("Touch the Mac") {
                    Label("In direct-touch mode, tap to click. Move one finger to drag.", systemImage: "hand.tap")
                    Label("Use Keyboard in the toolbar to type on your Mac.", systemImage: "keyboard")
                }
                TrunklineSection("Zoom and move the view") {
                    Label("Pinch to zoom. When zoomed in, pan with two fingers.", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                TrunklineSection("Mac Spaces and windows") {
                    Label("Swipe left or right with three fingers to change Spaces.", systemImage: "arrow.left.arrow.right")
                    Label("Swipe up with three fingers for Mission Control. Swipe down for App windows.", systemImage: "rectangle.3.group")
                    Text("These actions use the Mac’s Control–Arrow keyboard shortcuts. You can also use the Spaces and windows menu.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                TrunklineSection("Physical monitors") {
                    Label("Use Displays in the toolbar to switch between connected Mac monitors. Each display keeps its own proportions.", systemImage: "display.2")
                    Text("Spaces are virtual desktops on a monitor. Create or rearrange them in Mission Control.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if #available(iOS 27.0, *), UIDevice.current.userInterfaceIdiom == .pad {
                    TrunklineSection("iPad external display") {
                        Text("Connect a display, then turn on Use external display in Spaces and windows. The full Mac desktop appears there while your iPad keeps its preview and controls. Close the desktop or turn the option off to stop output.")
                    }
                }
            }.nativeWorkspaceStyle().font(.body)
                .navigationTitle("Desktop gestures")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showGestures = false } } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
    @ViewBuilder private var shortcutCommands: some View {
            if adaptive, let state = model.controls.snapshot?.desktopQuality {
                if state.failed { Text("Adaptive quality paused") }
                else if state.applied > 0 { Text("Video: \(state.applied / 1000) Mbps") }
            }
            Button("Send text…") { paste = true }
            Menu("Editing") {
                key("Copy", 0x43, 0x08); key("Paste", 0x56, 0x08); key("Cut", 0x58, 0x08)
                key("Undo", 0x5A, 0x08); key("Select all", 0x41, 0x08); key("Save", 0x53, 0x08)
            }
            Menu("Navigation") {
                key("Escape", 0x1B); key("Tab", 0x09)
                key("Home", 0x24); key("End", 0x23); key("Page up", 0x21); key("Page down", 0x22)
                key("Left", 0x25); key("Up", 0x26); key("Right", 0x27); key("Down", 0x28)
            }
            Menu("Function keys") { ForEach(1...12, id: \.self) { number in key("F\(number)", UInt16(0x6F + number)) } }
            Menu("System") {
                key("Switch app", 0x09, 0x08); key("Spotlight", 0x20, 0x08)
                key("Interrupt", 0x43, 0x02)
            }
    }
    private var trailingTools: some View {
        Group {
            Menu { shortcutCommands } label: { Image(systemName: "command").frame(width: 44, height: 44) }
                .accessibilityLabel("Shortcuts")
            DesktopDisplayMenu(controls: model.controls, compact: true) { pendingMonitorID = $0 }
            tool("Mac controls", "slider.horizontal.3") { showControls = true }
            tool("Hide toolbar", "chevron.down") { toolbarVisible = false }
        }
    }
    private func tool(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 44, height: 44) }.accessibilityLabel(title)
    }
    private func key(_ title: String, _ code: UInt16, _ modifiers: UInt8 = 0) -> some View {
        Button(title) { engine.sendKey(code, modifiers: modifiers) }
    }

}

/// Keep focus inside the presented hierarchy. The editor follows the remaining
/// container height when the keyboard, rotation or an iPad window resizes it.
private struct DesktopTextSheet: View {
    @Binding var text: String
    let cancel: () -> Void
    let send: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                Form {
                    TrunklineSection {
                        TextEditor(text: $text)
                            .focused($focused)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: max(44, min(180, geometry.size.height - 120)))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityLabel("Text to send")
                        PasteButton(payloadType: String.self) { text = $0.joined(separator: "\n") }
                    } footer: {
                        Text("Review commands before sending. Newlines may execute them on your Mac.")
                    }
                }
                .nativeWorkspaceStyle()
            }
            .navigationTitle("Send text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send", action: send).disabled(text.isEmpty || text.utf8.count > 65536)
                }
            }
            .defaultFocus($focused, true)
            .task { focused = true }
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Exercises the production viewer chrome without creating a streaming controller.
struct DesktopExperienceReview: View {
    @ObservedObject var model: ConnectionModel
    private let engine = TrunklineStream()
    private let configuration = StreamConfiguration()
    var body: some View {
        DesktopScreen(engine: engine, config: configuration, model: model, close: {})
    }
}
#endif
