#if canImport(TrunklineCore)
import TrunklineCore
#endif
#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Simulator-only presentation fixtures. No credentials, transport or remote actions.
@MainActor
struct ExperienceReview: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model: ConnectionModel
    private let section = ProcessInfo.processInfo.environment["TRUNKLINE_REVIEW_SECTION"] ?? "desktop"
    init() {
        let section = ProcessInfo.processInfo.environment["TRUNKLINE_REVIEW_SECTION"] ?? "desktop"
        // Keep review state separate from the user's normal saved Macs and preferences.
        let suite = "com.trunkline.ui-review"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        if section != "connection" && section != "scanner" {
            var saved = SavedMacStore(defaults: defaults)
            let studio = try! PairingDetails(host: "studio-mac.example.invalid", port: 443,
                                            fingerprint: String(repeating: "a", count: 64))
            let laptop = try! PairingDetails(host: "macbook.example.invalid", port: 443,
                                            fingerprint: String(repeating: "b", count: 64))
            saved.save(laptop, name: "MacBook Pro")
            saved.save(studio, name: "Studio Mac")
        }
        let creatingTerminal = ProcessInfo.processInfo.environment["TRUNKLINE_REVIEW_CREATING_TERMINAL"] == "1"
        let model = ConnectionModel(defaults: defaults, terminalCreationTimeout: creatingTerminal ? 600 : 15)
        let finderWindowID = UUID(uuidString: "00000000-0000-4000-8000-000000000010")!
        let safariWindowID = UUID(uuidString: "00000000-0000-4000-8000-000000000011")!
        if !section.hasPrefix("connection-") { model.pairingText = "" }
        if section == "connection-connecting" {
            model.phase = .connecting
            model.connectionStatus = "Connecting to Studio Mac…"
        }
        model.name = "Studio Mac"
        model.roundTripMS = 9
        model.files.send = nil
        model.files.configure(fileFeatures: ProcessInfo.processInfo.environment["TRUNKLINE_REVIEW_LEGACY_FILES"] == "1"
                              ? nil : FileFeature.allCases.map(\.rawValue))
        model.controls.send = nil
        _ = model.controls.handle(.controls(MacControlSnapshot(
            apps: [MacApplication(pid: 10, name: "Finder", bundleID: "com.apple.finder", active: false),
                   MacApplication(pid: 11, name: "Safari", bundleID: "com.apple.Safari", active: true)],
            windows: [MacWindow(id: safariWindowID, title: "Project notes", minimized: false, canMoveToDisplay: true)],
            displays: [MacDisplayInfo(id: 1, name: "Built-in display", width: 3024, height: 1964)],
            volume: 0.4, muted: false, accessibility: true, frontmostApp: "Safari",
            installedApps: [MacInstalledApplication(name: "Activity Monitor", bundleID: "com.apple.ActivityMonitor"),
                MacInstalledApplication(name: "Finder", bundleID: "com.apple.finder"),
                MacInstalledApplication(name: "Safari", bundleID: "com.apple.Safari"),
                MacInstalledApplication(name: "System Settings", bundleID: "com.apple.systempreferences")],
            audioOutputs: [MacAudioOutput(id: "preview-speakers", name: "Mac speakers", selected: true),
                           MacAudioOutput(id: "preview-headphones", name: "Headphones", selected: false)],
            power: MacPowerCapability(actions: MacPowerAction.allCases.map(\.rawValue), authorizationRequired: false),
            windowScope: MacWindowScope(requestedPID: nil, application: MacApplication(pid: 11, name: "Safari", bundleID: "com.apple.Safari", active: true)))))
        if ProcessInfo.processInfo.environment["TRUNKLINE_REVIEW_MULTIPLE_DISPLAYS"] == "1", var state = model.controls.snapshot {
            state.displays.append(MacDisplayInfo(id: 74, name: "Studio Display", width: 2560, height: 1440))
            state.desktopDisplays = DesktopDisplaySelection(displays: [
                DesktopCaptureDisplay(id: "1", name: "Built-in display", width: 3024, height: 1964),
                DesktopCaptureDisplay(id: "74", name: "Studio Display", width: 2560, height: 1440)
            ], activeID: "1", preferredID: "1")
            _ = model.controls.handle(.controls(state))
        }
        let pagedWindows = ProcessInfo.processInfo.environment["TRUNKLINE_REVIEW_WINDOW_PAGES"] == "1"
        let pageCursor = UUID()
        let previewWindows = (1...5).map { MacWindow(id: UUID(), title: "Project notes · \($0)", minimized: false, canMoveToDisplay: true) }
        if pagedWindows, var state = model.controls.snapshot {
            state.windows = Array(previewWindows.prefix(3))
            state.windowPage = MacWindowPage(nextCursor: pageCursor, totalCount: 5)
            _ = model.controls.handle(.controls(state))
        }
        model.controls.send = { [weak controls = model.controls] message in
            if case let .control(request) = message, case let .desktopDisplay(id) = request.action,
               var snapshot = controls?.snapshot, let displays = snapshot.desktopDisplays?.displays {
                snapshot.desktopDisplays = DesktopDisplaySelection(displays: displays, activeID: id, preferredID: id)
                _ = controls?.handle(.controls(snapshot))
                _ = controls?.handle(.controlResult(MacControlResult(id: request.id)))
            }
            if case let .requestControls(pid, id, cursor, preserve) = message, var snapshot = controls?.snapshot {
                let application = snapshot.apps.first { pid == nil ? $0.active : $0.pid == pid }
                snapshot.windowScope = MacWindowScope(requestedPID: pid, application: application)
                snapshot.requestID = id
                snapshot.windows = [MacWindow(id: application?.pid == 10 ? finderWindowID : safariWindowID,
                    title: application?.pid == 10 ? "Documents" : "Project notes", minimized: false, canMoveToDisplay: true)]
                if pagedWindows {
                    let expanded = cursor == pageCursor || (preserve == true && controls?.snapshot?.windowPage?.nextCursor == nil)
                    snapshot.windows = expanded ? previewWindows : Array(previewWindows.prefix(3))
                    snapshot.windowPage = MacWindowPage(nextCursor: expanded ? nil : pageCursor, totalCount: 5)
                }
                _ = controls?.handle(.controls(snapshot))
            }
        }
        model.sessions = [TerminalSessionInfo(id: UUID(), title: "Project · build", kind: .shell, isRunning: true),
                          TerminalSessionInfo(id: UUID(), title: "Server · logs", kind: .shell, isRunning: true),
                          TerminalSessionInfo(id: UUID(), title: "Previous build", kind: .shell, isRunning: false)]
        if ProcessInfo.processInfo.environment["TRUNKLINE_REVIEW_EMPTY_TERMINALS"] == "1" { model.sessions = [] }
        if ProcessInfo.processInfo.environment["TRUNKLINE_REVIEW_LOADING_TERMINALS"] != "1" {
            model.receiveTerminalSessions(model.sessions)
        } else { model.sessions = [] }
        if creatingTerminal {
            // No channel exists in this fixture; show the production pending UI.
            model.phase = .connected
            model.createTerminal(.shell)
        }
        let entries = [RemoteFile(name: "Documents", path: "Documents", isDirectory: true, size: 0),
                       RemoteFile(name: "Design notes.pdf", path: "Design notes.pdf", isDirectory: false, size: 245760),
                       RemoteFile(name: "Glacier Fold — interface review and accessibility notes.pdf", path: "Glacier Fold — interface review and accessibility notes.pdf", isDirectory: false, size: 12582912),
                       RemoteFile(name: "Release 2.txt", path: "Release 2.txt", isDirectory: false, size: 1024),
                       RemoteFile(name: "Release 10.txt", path: "Release 10.txt", isDirectory: false, size: 4096)]
        let shownEntries = section == "files-empty" ? [] : entries
        model.files.entries = shownEntries
        model.files.clipboardText = "Project notes\nReview the latest build on Studio Mac."
        if section == "files-transfer" {
            model.files.transferName = "Design notes.pdf"
            model.files.progress = 0.42
        }
        if section == "files-downloaded" {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Review notes.txt")
            try? "Synthetic screenshot fixture. No remote file was downloaded.\n".write(to: url, atomically: true, encoding: .utf8)
            model.files.downloadedURL = url
        }
        model.files.send = { [weak files = model.files] message in
            if case let .listFiles(path) = message {
                let children = path.isEmpty ? shownEntries : [RemoteFile(name: "Project notes.txt", path: "\(path)/Project notes.txt", isDirectory: false, size: 2048)]
                _ = files?.handle(.fileList(path: path, entries: children))
            }
        }
        _model = StateObject(wrappedValue: model)
    }
    var body: some View {
        reviewContent
            .overlay(alignment: .topLeading) {
                Text("PREVIEW").font(.caption2).dynamicTypeSize(.large).foregroundStyle(.secondary)
                    .padding(6).background(.regularMaterial, in: Capsule()).padding(6)
                    .accessibilityIdentifier("ui-review-ready")
                    .accessibilityValue(colorScheme == .dark ? "dark" : "light")
                    .allowsHitTesting(false)
            }
    }
    @ViewBuilder private var reviewContent: some View {
        switch section {
        case "help": AppHelpView()
        case "desktop-session": DesktopExperienceReview(model: model)
        case "connection", "connection-saved", "connection-connecting": ConnectView(model: model)
        case "scanner": PairingScanner { _ in }
        case "clipboard": ClipboardView(files: model.files)
        case "terminal-detail", "terminal-ended":
            NavigationStack {
                if let session = section == "terminal-ended" ? model.sessions.last : model.sessions.first {
                    SessionDetail(model: model, session: session)
                }
            }
        default:
            ConnectedTabs(model: model, initialSelection: section.hasPrefix("files-") ? .files :
                WorkspaceSection(rawValue: section) ?? .desktop)
        }
    }
}
#endif
