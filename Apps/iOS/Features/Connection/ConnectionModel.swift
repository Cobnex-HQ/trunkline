import Foundation
import Combine
import Network
import LocalAuthentication
import UIKit
#if canImport(TrunklineCore)
import TrunklineCore
#endif

@MainActor
final class ConnectionModel: ObservableObject {
    enum Phase { case setup, connecting, authenticating, connected }
    @Published var phase: Phase = .setup
    @Published var useAwayAccess: Bool {
        didSet {
            defaults.set(useAwayAccess, forKey: "use-away-access")
            if let pairing = try? PairingDetails.parse(pairingText) {
                macStore.save(pairing, away: useAwayAccess); savedMacs = macStore.macs
            }
            if useAwayAccess { offerAwayAccess = false; cancelLocalProbe() }
        }
    }
    @Published private(set) var savedMacs: [SavedMac] = []
    private var macStore: SavedMacStore
    var preferences: MacPreferencesStore { MacPreferencesStore(defaults: defaults) }
    var selectedMacID: String? { (try? PairingDetails.parse(pairingText))?.fingerprint }
    @Published var offerAwayAccess = false
    @Published var connectionStatus = ""
    private var remote: RemoteConnection?
    private var preparing: Task<Void, Never>?
    private(set) var sessionPairingLink = ""
    var hasAwayAccess: Bool {
        guard let pairing = try? PairingDetails.parse(pairingText) else { return false }
        return pairing.remote != nil || SecretStore.contains(RemoteAccessTicket.storageKey(pairing.fingerprint))
    }
    @Published var pairingRequestID = UUID()
    var openPairingScanner = false
    @Published var pairingText: String
    @Published var passcode = ""
    @Published var rememberPasscode = false
    @Published var name = "Your Mac"
    @Published var diagnostic = ConnectionDiagnostic()
    @Published var error: String?
    @Published var roundTripMS: Int?
    @Published var desktopDisplay = DesktopDisplay.fallback
    @Published var sessions: [TerminalSessionInfo] = []
    @Published var selectedTerminalID: UUID?
    @Published var workspaceSection: WorkspaceSection = .desktop
    // Keep the authenticated credential only for this app process. Persistent
    // credentials remain in the user-presence-protected Keychain.
    private struct ResumeConnection {
        let pairingLink: String
        let passcode: String
        var terminalID: UUID?
    }
    private var resumeConnection: ResumeConnection?
    private var pendingTerminalRestore: UUID?
    private var handledLaunchResume = false
    private var isForeground = true
    private var windowFocused = true
    private let awakeID = UUID()
    private static var awakeWindows: Set<UUID> = []
    private let resumeStorageKey: String
    private var isUnlockingSaved = false
    @Published private(set) var hasLoadedTerminals = false
    @Published private(set) var isCreatingTerminal = false
    @Published private(set) var closingTerminalIDs: Set<UUID> = []
    private var terminalCloseDeadlines: [UUID: Task<Void, Never>] = [:]
    private var terminalIDsBeforeCreation: Set<UUID>?
    private var terminalCreationDeadline: Task<Void, Never>?
    #if DEBUG
    private var loggedTerminalOutput = false
    #endif
    var onTerminalData: ((UUID, Data, Bool) -> Void)?
    var onDesktopError: ((String, String?) -> Void)?
    func createTerminal(_ kind: TerminalKind) {
        guard phase == .connected, hasLoadedTerminals, !isCreatingTerminal else { return }
        terminalIDsBeforeCreation = Set(sessions.map(\.id))
        isCreatingTerminal = true
        error = nil
        terminalCreationDeadline = Task { [weak self, terminalCreationTimeout] in
            do { try await Task.sleep(for: .seconds(terminalCreationTimeout)) } catch { return }
            guard let self, self.isCreatingTerminal else { return }
            self.finishTerminalCreation()
            self.error = "The Mac hasn’t confirmed the new session. Check the session list before trying again."
            self.send(.listTerminals)
        }
        send(.createTerminal(kind: kind, title: ""))
    }
    private func finishTerminalCreation() {
        terminalCreationDeadline?.cancel(); terminalCreationDeadline = nil
        terminalIDsBeforeCreation = nil
        isCreatingTerminal = false
    }
    func isEndingTerminal(_ id: UUID) -> Bool {
        closingTerminalIDs.contains(id) || sessions.first(where: { $0.id == id })?.isStopping == true
    }
    func closeTerminal(_ id: UUID) {
        guard phase == .connected, sessions.contains(where: { $0.id == id }), !isEndingTerminal(id) else { return }
        closingTerminalIDs.insert(id)
        error = nil
        terminalCloseDeadlines[id] = Task { [weak self, terminalCloseTimeout] in
            do { try await Task.sleep(for: .seconds(terminalCloseTimeout)) } catch { return }
            guard let self, self.closingTerminalIDs.contains(id) else { return }
            self.finishTerminalClose(id)
            self.error = "The Mac hasn’t confirmed that the session stopped. Refresh the list before trying again."
            self.send(.listTerminals)
        }
        send(.closeTerminal(id: id))
    }
    private func finishTerminalClose(_ id: UUID) {
        terminalCloseDeadlines.removeValue(forKey: id)?.cancel()
        closingTerminalIDs.remove(id)
    }
    private func clearTerminalCloses() {
        for id in closingTerminalIDs { finishTerminalClose(id) }
    }
    func receiveTerminalSessions(_ sessions: [TerminalSessionInfo]) {
        let selectedWasRunning = self.sessions.first { $0.id == selectedTerminalID }?.isRunning == true
        self.sessions = sessions
        if let id = pendingTerminalRestore {
            selectedTerminalID = sessions.first(where: { $0.id == id && $0.isRunning })?.id
            pendingTerminalRestore = nil
        }
        for id in closingTerminalIDs where !sessions.contains(where: { $0.id == id }) { finishTerminalClose(id) }
        hasLoadedTerminals = true
        if let previousIDs = terminalIDsBeforeCreation,
           let created = sessions.first(where: { !previousIDs.contains($0.id) }) {
            selectedTerminalID = created.id
            finishTerminalCreation()
        }
        if let selected = selectedTerminalID, !sessions.contains(where: { $0.id == selected }) { selectedTerminalID = nil }
        if selectedWasRunning, let selected = selectedTerminalID,
           sessions.first(where: { $0.id == selected })?.isRunning == false { selectedTerminalID = nil }
    }
    func sendTerminalPaste(_ text: String, id: UUID) {
        let bytes = Array(("\u{1b}[200~" + text + "\u{1b}[201~").utf8)
        for offset in stride(from: 0, to: bytes.count, by: 16384) {
            send(.terminalInput(id: id, bytes: Data(bytes[offset..<min(bytes.count, offset+16384)])))
        }
    }
    let controls = ClientControls()
    let files = ClientFiles()
    private let defaults: UserDefaults
    private let heartbeatInterval: TimeInterval
    private let heartbeatTimeout: TimeInterval
    private let terminalCreationTimeout: TimeInterval
    private let terminalCloseTimeout: TimeInterval
    private let deviceIdentity: @MainActor (String) throws -> DeviceClaim
    private let makeChannel: @MainActor (PairingDetails) -> SecureChannel
    private let containsSavedSecret: (String) -> Bool
    private let unlockSavedSecret: @MainActor (String) async throws -> Data?
    init(defaults: UserDefaults = .standard, automaticallyResume: Bool = true, resumeStorageKey: String = "resume-mac-id", heartbeatInterval: TimeInterval = 5,
         heartbeatTimeout: TimeInterval = 15, terminalCreationTimeout: TimeInterval = 15, terminalCloseTimeout: TimeInterval = 10,
         deviceIdentity: @escaping @MainActor (String) throws -> DeviceClaim = { try DeviceIdentity.claim(macID: $0, name: UIDevice.current.name) },
         makeChannel: @escaping @MainActor (PairingDetails) -> SecureChannel = { SecureChannel(pairing: $0) },
         containsSavedSecret: @escaping (String) -> Bool = { SecretStore.contains($0) },
         unlockSavedSecret: @escaping @MainActor (String) async throws -> Data? = { key in
             let context = LAContext()
             guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your saved Mac connection") else { return nil }
             return SecretStore.read(key, context: context)
         }) {
        precondition(heartbeatInterval > 0 && heartbeatTimeout >= heartbeatInterval)
        precondition(terminalCreationTimeout > 0)
        precondition(terminalCloseTimeout > 0)
        self.defaults = defaults
        self.resumeStorageKey = resumeStorageKey
        self.handledLaunchResume = !automaticallyResume
        self.macStore = SavedMacStore(defaults: defaults)
        self.heartbeatInterval = heartbeatInterval
        self.heartbeatTimeout = heartbeatTimeout
        self.terminalCreationTimeout = terminalCreationTimeout
        self.terminalCloseTimeout = terminalCloseTimeout
        self.makeChannel = makeChannel
        self.deviceIdentity = deviceIdentity
        self.containsSavedSecret = containsSavedSecret
        self.unlockSavedSecret = unlockSavedSecret
        useAwayAccess = defaults.bool(forKey: "use-away-access")
        let selectionID = macStore.selectedID
        let selected = macStore.macs.first { $0.id == selectionID }
        pairingText = selected?.link ?? defaults.string(forKey: "pairing-link") ?? ""
        useAwayAccess = selected?.away ?? useAwayAccess
        name = selected?.name ?? "Your Mac"
        savedMacs = macStore.macs
        files.send = { [weak self] in self?.send($0) }
        files.clipboard.localRevision = { UIPasteboard.general.changeCount }
        files.clipboard.readLocal = { UIPasteboard.general.string }
        files.clipboard.writeLocal = { UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: $0]], options: [.localOnly: true]) }
        files.onReconnect = { [weak self] in self?.disconnect() }
        controls.send = { [weak self] in self?.send($0) }
        controls.onDisplaySelection = { [weak self] display in
            guard let self, let id = self.selectedMacID else { return }
            self.preferences.update(id) { $0.displayID = display.persistentID ?? display.id }
        }
    }
    private var savedCredentialKey: String? {
        guard let pairing = try? PairingDetails.parse(pairingText) else { return nil }
        let scoped = SavedMac.credentialKey(pairing.fingerprint)
        if containsSavedSecret(scoped) { return scoped }
        if let legacy = defaults.string(forKey: "credential-pairing"),
           (try? PairingDetails.parse(legacy))?.fingerprint == pairing.fingerprint,
           containsSavedSecret("client-passcode") { return "client-passcode" }
        return nil
    }
    var canUnlockSaved: Bool { savedCredentialKey != nil }
    func selectMac(_ id: String) {
        guard phase == .setup, let mac = savedMacs.first(where: { $0.id == id }) else { return }
        clearResume()
        cancelLocalProbe()
        passcode = ""; rememberPasscode = false; error = nil; offerAwayAccess = false
        pairingText = mac.link; name = mac.name; useAwayAccess = mac.away
        macStore.select(id); pairingRequestID = UUID()
        checkLocalRoute()
    }
    func switchMac(_ id: String) {
        guard savedMacs.contains(where: { $0.id == id }), id != selectedMacID else { return }
        disconnect(); selectMac(id)
    }
    private var channel: SecureChannel?
    private var heartbeat: Timer?
    private var handshakeTimeout: DispatchWorkItem?
    private var pingSent: TimeInterval?
    private var connectionID = UUID()

    func receivePairingLink(_ url: URL) {
        guard phase == .setup else { return }
        do {
            let pairing = try PairingDetails.parse(url.absoluteString)
            clearResume()
            if let saved = defaults.string(forKey: "pairing-link"),
               let previous = try? PairingDetails.parse(saved), previous.fingerprint == pairing.fingerprint,
               SecretStore.read(DesktopTrustKey.current(pairing)) == nil,
               let certificate = SecretStore.read(DesktopTrustKey.legacy(previous)) {
                try SecretStore.write(certificate, key: DesktopTrustKey.current(pairing))
            }
            if pairingText != pairing.link { passcode = "" }
            pairingText = try saveRemoteTicket(pairing).link
            macStore.save(try PairingDetails.parse(pairingText))
            savedMacs = macStore.macs
            if let selected = savedMacs.first(where: { $0.id == pairing.fingerprint }) {
                name = selected.name; useAwayAccess = selected.away
            }
            rememberPasscode = false; offerAwayAccess = false
            checkLocalRoute()
            error = nil
            pairingRequestID = UUID()
        } catch { self.error = error.localizedDescription }
    }

    private func saveRemoteTicket(_ pairing: PairingDetails) throws -> PairingDetails {
        if let remote = pairing.remote {
            try SecretStore.write(JSONEncoder().encode(remote), key: RemoteAccessTicket.storageKey(pairing.fingerprint))
        }
        return try PairingDetails(host: pairing.host, port: pairing.port, fingerprint: pairing.fingerprint)
    }
    func connect() {
        guard phase == .setup, isForeground else { return }
        cancelLocalProbe(); offerAwayAccess = false
        diagnostic.begin(route: useAwayAccess ? .away : .local)
        do {
            let pairing = try saveRemoteTicket(PairingDetails.parse(pairingText))
            pairingText = pairing.link
            guard !passcode.isEmpty else { error = "Enter the connection passcode you set on your Mac."; return }
            if !useAwayAccess { beginChannel(pairing); return }
            guard let data = SecretStore.read(RemoteAccessTicket.storageKey(pairing.fingerprint)) else {
                error = "Enable Away access on your Mac, then scan its updated QR code."; return
            }
            let ticket = try JSONDecoder().decode(RemoteAccessTicket.self, from: data)
            try ticket.validate()
            phase = .connecting; error = nil; connectionStatus = "Establishing a direct connection…"
            setAwake(true)
            let remote = RemoteConnection(); self.remote = remote
            remote.onLost = { [weak self] message in self?.disconnect(); self?.error = message; self?.diagnostic.fail(.interrupted) }
            let id = UUID(); connectionID = id
            preparing = Task { [weak self] in
                do {
                    try await remote.start(ticket)
                    guard let self, self.connectionID == id, !Task.isCancelled else { return }
                    let local = try PairingDetails(host: "127.0.0.1", port: pairing.port, fingerprint: pairing.fingerprint)
                    self.beginChannel(local)
                } catch {
                    guard let self, self.connectionID == id else { return }
                    self.disconnect(); self.error = error.localizedDescription
                    let remoteError = error as NSError
                    self.diagnostic.fail(remoteError.domain == "Remote" && remoteError.code == 2 ? .clientBusy : .directRouteUnavailable)
                }
            }
        } catch { self.error = error.localizedDescription; phase = .setup }
    }
    private func beginChannel(_ pairing: PairingDetails) {
            guard !passcode.isEmpty else { error = "Enter the connection passcode you set on your Mac."; return }
            diagnostic.advance(.secureConnection)
            sessionPairingLink = pairing.link
            connectionStatus = useAwayAccess ? "Direct connection established. Authenticating…" : "Connecting to your Mac…"
            let connectionLink = pairingText
            let shouldRememberPasscode = rememberPasscode
            var connectionPasscode = passcode
            error = nil; phase = .connecting
            let id = UUID(); connectionID = id
            let channel = makeChannel(pairing)
            self.channel = channel
            channel.onReady = { [weak self, weak channel] in
                guard let self, self.connectionID == id else { return }
                self.phase = .authenticating
                self.diagnostic.advance(.authentication)
                do {
                    let device = try self.deviceIdentity(pairing.fingerprint)
                    channel?.send(.authenticate(passcode: connectionPasscode, device: device))
                } catch { self.disconnect(); self.error = error.localizedDescription }
            }
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, self.connectionID == id, self.phase != .connected else { return }
                let message = self.phase == .connecting
                    ? "Couldn’t reach your Mac. Turn on My Mac → Sharing on the Mac, allow Local Network access on this device, and check that both devices use the same Wi-Fi or private VPN."
                    : "The Mac didn’t confirm your passcode. Check the Mac’s connection status and try again."
                let cause: ConnectionFailureCause = self.phase == .authenticating ? .authenticationTimeout : .unreachable
                self.disconnect(); self.error = message; self.diagnostic.fail(cause)
            }
            handshakeTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 18, execute: timeout)
            channel.onMessage = { [weak self] message in
                guard let self, self.connectionID == id else { return }
                if self.phase == .connected {
                    if self.controls.handle(message) {
                        if case .controls = message, let id = self.selectedMacID {
                            self.controls.restoreDisplay(from: self.preferences.load(id))
                        }
                        return
                    }
                    switch message {
                    case let .terminals(sessions):
                        self.receiveTerminalSessions(sessions)
                        return
                    case let .terminalOutput(id, bytes, reset):
                        #if DEBUG
                        if self.useAwayAccess && !self.loggedTerminalOutput && !bytes.isEmpty {
                            self.loggedTerminalOutput = true; print("TRUNKLINE_REMOTE terminal_output_received"); fflush(stdout)
                        }
                        #endif
                        self.onTerminalData?(id, bytes, reset); return
                    case let .operationError(error, context):
                        self.handleOperationError(error, context: context)
                        return
                    default: break
                    }
                    if self.files.handle(message) { return }
                }
                switch message {
                case let .accepted(name, display, fileFeatures):
                    guard self.phase == .authenticating else { return }
                    self.handshakeTimeout?.cancel(); self.handshakeTimeout = nil
                    #if DEBUG
                    if self.useAwayAccess { print("TRUNKLINE_REMOTE companion_authenticated"); fflush(stdout) }
                    self.loggedTerminalOutput = false
                    #endif
                    self.files.configure(fileFeatures: fileFeatures)
                    self.name = name; self.desktopDisplay = display; self.phase = .connected
                    self.diagnostic.advance(.connected)
                    defaults.set(connectionLink, forKey: "pairing-link")
                    if let paired = try? PairingDetails.parse(connectionLink) {
                        self.files.configureClipboard(macID: paired.fingerprint, defaults: self.defaults)
                        if !self.windowFocused { self.files.clipboard.pause() }
                        self.macStore.save(paired, name: name, away: self.useAwayAccess)
                        self.savedMacs = self.macStore.macs
                        self.defaults.set(paired.fingerprint, forKey: self.resumeStorageKey)
                    }
                    if shouldRememberPasscode {
                        do {
                            let paired = try PairingDetails.parse(connectionLink)
                            try SecretStore.writeProtected(Data(connectionPasscode.utf8), key: SavedMac.credentialKey(paired.fingerprint))
                        } catch { self.error = "Connected, but the passcode could not be saved." }
                    }
                    self.resumeConnection = ResumeConnection(pairingLink: connectionLink, passcode: connectionPasscode)
                    self.handledLaunchResume = true
                    connectionPasscode = ""
                    self.passcode = ""
                    self.setAwake(true)
                    let heartbeat = Timer(timeInterval: self.heartbeatInterval, repeats: true) { [weak self] timer in
                        MainActor.assumeIsolated {
                        guard let self, self.connectionID == id, self.phase == .connected else { timer.invalidate(); return }
                        self.checkHeartbeat()
                        }
                    }
                    self.heartbeat = heartbeat
                    RunLoop.main.add(heartbeat, forMode: .common)
                    self.checkHeartbeat()
                    self.channel?.send(.listTerminals)
                case .pong:
                    if self.phase == .connected, let sent = self.pingSent {
                        self.roundTripMS = Int(max(0, ProcessInfo.processInfo.systemUptime - sent) * 1000)
                        self.pingSent = nil
                    }
                case let .failure(message, cause):
                    self.disconnect(); self.error = message; self.diagnostic.fail(cause ?? .unknown)
                default: break
                }
            }
            channel.onClose = { [weak self, weak channel] reason in
                connectionPasscode = ""
                guard let self, self.connectionID == id else { return }
                self.diagnostic.fail(channel?.failureCause ?? .interrupted)
                self.channel = nil; self.remote?.stop(); self.remote = nil; self.resetSession(); self.error = reason
                self.checkLocalRoute()
            }
            channel.start()
    }
    func unlockSaved() async {
        guard canUnlockSaved, phase == .setup, isForeground, !isUnlockingSaved else { return }
        isUnlockingSaved = true
        defer { isUnlockingSaved = false }
        let expectedPairing = pairingText
        let expectedConnectionID = connectionID
        guard let key = savedCredentialKey else { return }
        do {
            guard let data = try await unlockSavedSecret(key), pairingText == expectedPairing,
                  connectionID == expectedConnectionID, isForeground, !Task.isCancelled,
                  let value = String(data: data, encoding: .utf8) else { return }
            guard phase == .setup else { return }
            if key == "client-passcode", let pairing = try? PairingDetails.parse(expectedPairing) {
                try SecretStore.writeProtected(data, key: SavedMac.credentialKey(pairing.fingerprint))
                SecretStore.delete(key); defaults.removeObject(forKey: "credential-pairing")
            }
            passcode = value; connect()
        } catch {
            if connectionID == expectedConnectionID, isForeground, !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
    func forget() {
        guard let pairing = try? PairingDetails.parse(pairingText) else { return }
        disconnect()
        SecretStore.delete(RemoteAccessTicket.storageKey(pairing.fingerprint))
        SecretStore.delete(SavedMac.credentialKey(pairing.fingerprint))
        if let legacy = defaults.string(forKey: "credential-pairing"),
           (try? PairingDetails.parse(legacy))?.fingerprint == pairing.fingerprint {
            SecretStore.delete("client-passcode"); defaults.removeObject(forKey: "credential-pairing")
        }
        MacPreferencesStore(defaults: defaults).remove(pairing.fingerprint)
        macStore.remove(pairing.fingerprint); savedMacs = macStore.macs
        defaults.removeObject(forKey: "pairing-link")
        pairingText = ""; passcode = ""; rememberPasscode = false
        if let next = macStore.selectedID { selectMac(next) }
    }
    func disconnect() {
        clearResume()
        workspaceSection = .desktop
        passcode = ""
        stopConnection()
    }
    private func clearResume() {
        connectionID = UUID()
        resumeConnection = nil
        pendingTerminalRestore = nil
        handledLaunchResume = true
        defaults.removeObject(forKey: self.resumeStorageKey)
    }
    private func stopConnection() {
        cancelLocalProbe()
        connectionID = UUID()
        preparing?.cancel(); preparing = nil
        remote?.stop(); remote = nil
        channel?.onClose = nil; channel?.close(); channel = nil
        resetSession()
    }
    func applicationDidEnterBackground() {
        isForeground = false
        if phase == .connected { resumeConnection?.terminalID = selectedTerminalID }
        // Release the host's single-device slot and stop streaming. This is a
        // suspension, not the user's explicit Disconnect action.
        stopConnection()
        passcode = ""
    }
    func applicationDidBecomeActive() async {
        guard !Task.isCancelled else { return }
        isForeground = true
        if phase == .connected { if windowFocused { files.clipboard.activate() }; return }
        guard phase == .setup else { return }
        if let resume = resumeConnection {
            guard pairingText == resume.pairingLink else { clearResume(); checkLocalRoute(); return }
            pendingTerminalRestore = resume.terminalID
            passcode = resume.passcode
            rememberPasscode = false
            connect()
        } else if !handledLaunchResume {
            handledLaunchResume = true
            if let id = selectedMacID, defaults.string(forKey: self.resumeStorageKey) == id, canUnlockSaved {
                await unlockSaved()
            }
        }
        if phase == .setup { checkLocalRoute() }
    }
    private var localProbe: SecureChannel?
    private var localProbeDeadline: DispatchWorkItem?
    private var routeGeneration = UUID()
    private var networkAvailable = false
    private var routeMonitoringStarted = false
    private let pathMonitor = NWPathMonitor()
    func startRouteMonitoring() {
        guard !routeMonitoringStarted else { return }
        routeMonitoringStarted = true
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in self?.networkChanged(available: path.status == .satisfied) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.trunkline.route"))
    }
    func networkChanged(available: Bool) {
        networkAvailable = available
        offerAwayAccess = false
        checkLocalRoute()
    }
    func checkLocalRoute() {
        cancelLocalProbe()
        guard isForeground, networkAvailable, phase == .setup, !useAwayAccess, hasAwayAccess,
              let pairing = try? PairingDetails.parse(pairingText) else { return }
        let generation = routeGeneration
        let probe = makeChannel(pairing); localProbe = probe
        probe.onReady = { [weak self] in self?.finishLocalProbe(generation, reachable: true) }
        probe.onClose = { [weak self] _ in self?.finishLocalProbe(generation, reachable: false) }
        let deadline = DispatchWorkItem { [weak self] in self?.finishLocalProbe(generation, reachable: false) }
        localProbeDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: deadline)
        probe.start()
    }
    private func finishLocalProbe(_ generation: UUID, reachable: Bool) {
        guard generation == routeGeneration else { return }
        cancelLocalProbe()
        offerAwayAccess = !reachable && phase == .setup && !useAwayAccess && hasAwayAccess
    }
    private func cancelLocalProbe() {
        routeGeneration = UUID()
        localProbeDeadline?.cancel(); localProbeDeadline = nil
        localProbe?.onClose = nil; localProbe?.close(); localProbe = nil
    }
    func chooseAwayAccess() { useAwayAccess = true; error = nil }
    func refreshSavedMacs() {
        macStore.refresh()
        if savedMacs != macStore.macs { savedMacs = macStore.macs }
    }
    func setWindowFocused(_ focused: Bool) {
        windowFocused = focused
        if focused && isForeground && phase == .connected { files.clipboard.activate() }
        else { files.clipboard.pause() }
    }
    func refreshAwakeState() { UIApplication.shared.isIdleTimerDisabled = !Self.awakeWindows.isEmpty }
    private func setAwake(_ awake: Bool) {
        if awake { Self.awakeWindows.insert(awakeID) }
        else { Self.awakeWindows.remove(awakeID) }
        UIApplication.shared.isIdleTimerDisabled = !Self.awakeWindows.isEmpty
    }
    deinit {
        pathMonitor.cancel()
        let id = awakeID
        Task { @MainActor in
            Self.awakeWindows.remove(id)
            UIApplication.shared.isIdleTimerDisabled = !Self.awakeWindows.isEmpty
        }
    }

    func handleOperationError(_ text: String, context: OperationContext?) {
        switch context?.domain {
        case .files, .clipboard:
            files.handle(.operationError(text, context: context))
        case .terminal:
            finishTerminalCreation(); clearTerminalCloses(); error = text
        case .desktop:
            if let onDesktopError { onDesktopError(text, context?.requestID) }
            else { error = text }
        case .general:
            error = text
        case nil:
            // Older hosts cannot identify the source. Preserve their behavior.
            finishTerminalCreation()
            if files.isBusy { files.handle(.operationError(text)) }
            else { error = text }
        }
    }
    func send(_ message: WireMessage) { if phase == .connected { channel?.send(message) } }
    private func checkHeartbeat() {
        guard phase == .connected else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let sent = pingSent {
            guard now - sent >= heartbeatTimeout else { return }
            disconnect()
            error = "Connection lost. Check your Mac and network, then reconnect."
            diagnostic.fail(.interrupted)
            checkLocalRoute()
        } else {
            pingSent = now
            channel?.send(.ping)
        }
    }
    private func resetSession() {
        controls.reset()
        finishTerminalCreation()
        clearTerminalCloses()
        hasLoadedTerminals = false
        sessions = []; selectedTerminalID = nil; onTerminalData = nil; onDesktopError = nil
        files.reset(preserveResumable: true)
        sessionPairingLink = ""; connectionStatus = ""
        phase = .setup; heartbeat?.invalidate(); heartbeat = nil
        handshakeTimeout?.cancel(); handshakeTimeout = nil
        roundTripMS = nil; pingSent = nil
        setAwake(false)
    }
}
