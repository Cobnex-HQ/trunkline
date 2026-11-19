import AppKit
import Network
import Combine
import SystemConfiguration
#if canImport(TrunklineCore)
import TrunklineCore
#endif
import IOKit.pwr_mgt

@MainActor
final class HostModel: ObservableObject {
    @Published private(set) var deviceAccess = DeviceAccessPolicy()
    @Published private(set) var updatingDeviceAccess = false
    private var devicePolicyURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Trunkline/device-access.json")
    }
    private func saveDeviceAccess(_ policy: DeviceAccessPolicy) throws {
        try FileManager.default.createDirectory(at: devicePolicyURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(policy).write(to: devicePolicyURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: devicePolicyURL.path)
        deviceAccess = policy
    }
    func approveDevice(_ id: UUID) {
        var policy = deviceAccess
        policy.approve(id)
        do { try saveDeviceAccess(policy) } catch { self.error = error.localizedDescription }
    }
    func requireDeviceApproval() {
        var policy = deviceAccess
        policy.requireApproval()
        do { try saveDeviceAccess(policy) } catch { self.error = error.localizedDescription }
    }
    func revokeDevice(_ id: UUID) async {
        guard !updatingDeviceAccess else { return }
        updatingDeviceAccess = true
        defer { updatingDeviceAccess = false }
        let restartSharing = isRunning
        do {
            try sunshine.requirePairingReset()
            var policy = deviceAccess
            policy.revoke(id)
            try saveDeviceAccess(policy)
            stop()
            resumableFiles = ResumableFileService()
            try await sunshine.resetPairings()
            if restartSharing { await start() }
        } catch {
            stop()
            self.error = "Sharing is off. Device access could not be updated safely. " + error.localizedDescription
        }
    }
    @Published var status = "Remote access is off"
    @Published var isRunning = false
    @Published var isConnected = false
    @Published var isStarting = false
    @Published var fingerprint = ""
    @Published var sharedFolderPath = UserDefaults.standard.string(forKey: "shared-folder") ?? ""
    func chooseSharedFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "Only this folder will be accessible through Trunkline file transfer."
        if panel.runModal() == .OK, let url = panel.url, url.path != sharedFolderPath {
            HostSharingAction.changeFolder.perform(connected: isConnected, runningTerminals: terminals.runningCount) {
                stop(); sharedFolderPath = url.path
                UserDefaults.standard.set(url.path, forKey: "shared-folder")
            }
        }
    }
    @Published var address = ""
    @Published var error: String?
    @Published var hasPasscode = SecretStore.contains("host-passcode")
    private var listener: NWListener?
    private var authentication: PreparedHostAuthentication?
    private lazy var controls = MacControls(awakeState: { [weak self] in self?.keepAwake.remoteState },
                                           setAwake: { [weak self] mode in
        guard let self else { throw MacControlError.unavailable }
        try self.keepAwake.applyRemotely(mode)
    })
    private var controlsTask: Task<Void, Never>?
    private var resumableFiles = ResumableFileService()
    private var snapshotTask: Task<Void, Never>?
    private let desktopPairing = DesktopPairingCoordinator()
    private var startup = AccessStartup()
    private var startupTimeout: Task<Void, Never>?
    private var channels: [UUID: SecureChannel] = [:]
    private var admission = SessionAdmission()
    private var activeID: UUID? { admission.owner }
    private var limiter: AttemptLimiter = {
        guard let data = UserDefaults.standard.data(forKey: "attempt-limiter"), let value = try? JSONDecoder().decode(AttemptLimiter.self, from: data) else { return AttemptLimiter() }
        return value
    }()
    let away = AwayAccessHost()
    private var awayObservation: AnyCancellable?
    private var awayAwakeObservation: AnyCancellable?
    let sunshine = DesktopHost()
    let keepAwake = KeepAwakeManager()
    let terminals = TerminalSessions()

    init() {
        if FileManager.default.fileExists(atPath: devicePolicyURL.path) {
            do { deviceAccess = try JSONDecoder().decode(DeviceAccessPolicy.self, from: Data(contentsOf: devicePolicyURL)) }
            catch {
                deviceAccess.requireApproval()
                try? sunshine.requirePairingReset()
                self.error = "Saved device approvals could not be read. New connections require approval on this Mac."
            }
        }
        awayObservation = away.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        awayAwakeObservation = away.$enabled.combineLatest($isRunning).sink { [weak self] enabled, running in
            self?.keepAwake.setAwayAccessActive(enabled && running)
        }
        let hostname = (SCDynamicStoreCopyLocalHostName(nil) as String?).map { $0 + ".local" } ?? "localhost"
        let store = SCDynamicStoreCreate(nil, "com.macphone.address" as CFString, nil, nil)
        let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        let interface = global?["PrimaryInterface"] as? String ?? "en0"
        let network = SCDynamicStoreCopyValue(store, "State:/Network/Interface/\(interface)/IPv4" as CFString) as? [String: Any]
        address = PairingAddress.preferred(addresses: network?["Addresses"] as? [String] ?? [], hostname: hostname)
    }
    func authorizeCredentials() async {
        do {
            try await Task.detached {
                for key in ["host-passcode", "identity-password", "sunshine-management-password"] {
                    _ = try SecretStore.readHostSecret(key, allowInteraction: true)
                }
            }.value
            await start()
        } catch { self.error = error.localizedDescription }
    }
    var pairingLink: String {
        (try? PairingDetails(host: address, port: 47995, fingerprint: fingerprint, remote: away.ticket))?.link ?? ""
    }
    func startOnLaunchIfReady() async {
        guard HostLaunchPolicy.shouldStartAccess(hasPasscode: hasPasscode) else { return }
        await start()
    }
    @discardableResult func savePasscode(_ passcode: String) -> Bool {
        guard HostSharingAction.changePasscode.perform(connected: isConnected, runningTerminals: terminals.runningCount, operation: {}) else { return false }
        error = nil
        do {
            let record = try PasscodeRecord(passcode: passcode)
            try SecretStore.write(JSONEncoder().encode(record), key: "host-passcode")
            hasPasscode = true
            // Changing the passcode revokes every current connection.
            stop()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func requestTurnOffSharing() {
        HostSharingAction.turnOff.perform(connected: isConnected, runningTerminals: terminals.runningCount) { stop() }
    }
    func requestDisconnectDevice() {
        HostSharingAction.disconnect.perform(connected: isConnected, runningTerminals: terminals.runningCount) { disconnect() }
    }
    func requestDisableAway() {
        HostSharingAction.disableAway.perform(connected: isConnected, runningTerminals: terminals.runningCount) { away.disable() }
    }
    private func recordReadiness(_ state: String, reason: String? = nil) {
        #if DEBUG
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Trunkline")
        let value: [String: Any] = ["state": state, "reason": reason ?? "", "time": Date().timeIntervalSince1970]
        if let data = try? JSONSerialization.data(withJSONObject: value) {
            let url = root.appendingPathComponent("host-readiness.json")
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        #endif
    }
    func start() async {
        guard hasPasscode, let token = startup.begin() else { return }
        isStarting = true; error = nil; status = "Preparing secure connection…"
        recordReadiness("preparing")
        startupTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, self.startup.timedOut(token) else { return }
            self.stop()
            self.status = "Startup timed out"
            self.error = "Remote access didn’t become ready. Check for a macOS Keychain or Local Network permission prompt, allow access for Trunkline, then try again."
        }
        do {
            let prepared = try await Task.detached(priority: .userInitiated) {
                guard let record = try SecretStore.readHostSecret("host-passcode") else { throw MacPhoneError.cryptoFailure }
                return (try PreparedHostAuthentication(record: record), try HostIdentity.load())
            }.value
            guard startup.accepts(token) else { return }
            authentication = prepared.0
            let identity = prepared.1
            try sunshine.prepareCredentials()
            fingerprint = identity.fingerprint
            let tls = NWProtocolTLS.Options()
            guard let protocolIdentity = sec_identity_create(identity.identity) else { throw MacPhoneError.cryptoFailure }
            sec_protocol_options_set_local_identity(tls.securityProtocolOptions, protocolIdentity)
            sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
            let tcp = NWProtocolTCP.Options(); tcp.noDelay = true
            let listener = try NWListener(using: NWParameters(tls: tls, tcp: tcp), on: 47995)
            listener.newConnectionHandler = { [weak self] connection in
                DispatchQueue.main.async {
                    guard let self, self.startup.accepts(token) else { connection.cancel(); return }
                    self.accept(connection)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                guard let self, self.startup.accepts(token) else { return }
                switch state {
                case .ready:
                    self.startup.ready(token)
                    self.startupTimeout?.cancel(); self.startupTimeout = nil
                    self.isStarting = false; self.isRunning = true
                    self.status = "Ready for your iPhone or iPad"
                    self.recordReadiness("ready")
                    self.away.start()
                    self.sunshine.setEnabled(true)
                    Task { await self.sunshine.start() }
                case let .failed(error): self.error = error.localizedDescription; self.stop()
                case .waiting: self.status = "Waiting for the network…"
                default: break
                }
                }
            }
            self.listener = listener
            listener.start(queue: .main)
        } catch {
            guard startup.failed(token) else { return }
            startupTimeout?.cancel(); startupTimeout = nil
            isStarting = false; isRunning = false
            status = "Could not start remote access"
            recordReadiness("failed", reason: error.localizedDescription)
            self.error = error.localizedDescription
        }
    }
    func stop() {
        away.stop(); authentication = nil
        startup.stop(); isStarting = false
        startupTimeout?.cancel(); startupTimeout = nil
        sunshine.stop()
        listener?.cancel(); listener = nil
        let old = channels; channels.removeAll()
        old.values.forEach { $0.close("Remote access stopped on Mac.") }
        endSession()
        isRunning = false; status = "Remote access is off"
    }
    func disconnect() {
        sunshine.stop()
        if let activeID { channels[activeID]?.close("Disconnected on Mac.") }
    }
    private func accept(_ connection: NWConnection) {
        guard channels.count < 4, limiter.isAllowed() else { connection.cancel(); return }
        let id = UUID()
        let channel = SecureChannel(connection: connection)
        channels[id] = channel
        let files = HostFiles(root: sharedFolderPath.isEmpty ? nil : URL(fileURLWithPath: sharedFolderPath, isDirectory: true), resumable: resumableFiles)
        var authenticated = false
        var lastActivity = Date()
        let acceptedAt = Date()
        let watchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak channel] _ in
            MainActor.assumeIsolated {
            if (!authenticated && Date().timeIntervalSince(acceptedAt) > 15) || Date().timeIntervalSince(lastActivity) > 40 || Date().timeIntervalSince(acceptedAt) > 8 * 3600 {
                channel?.close("Session expired. Connect again.")
            }
            }
        }
        channel.onMessage = { [weak self, weak channel] message in
            guard let self, let channel else { return }
            lastActivity = Date()
            if !authenticated {
                guard case let .authenticate(passcode, device) = message, self.limiter.isAllowed() else {
                    channel.reject("Authentication failed. Try again in one minute.", cause: .rateLimited); return
                }
                let authentication = self.authentication
                switch self.admission.admit(id, verify: { authentication?.verify(passcode) == true }) {
                case .busy:
                    channel.reject("This Mac is in use on another device. Disconnect there before connecting here.", cause: .hostBusy)
                    return
                case .invalidCredentials:
                    self.limiter.recordFailure(); self.persistLimiter()
                    channel.reject("Incorrect connection passcode. After five attempts, wait one minute.", cause: .authenticationRejected)
                    return
                case .accepted: break
                }
                var policy = self.deviceAccess
                let decision = policy.authenticate(device)
                do { try self.saveDeviceAccess(policy) }
                catch {
                    self.admission.release(id)
                    channel.reject("Device approval could not be saved on the Mac.", cause: .deviceApprovalRequired)
                    return
                }
                guard decision == .allowed else {
                    self.admission.release(id)
                    let cause: ConnectionFailureCause = decision == .revoked ? .deviceRevoked : .deviceApprovalRequired
                    channel.reject(cause.guidance, cause: cause)
                    return
                }
                self.limiter.reset(); self.persistLimiter()
                authenticated = true; self.isConnected = true
                self.status = "Your device is connected"
                self.recordReadiness("authenticated")
                if self.sunshine.desktopEnabled { Task { await self.sunshine.start() } }
                self.terminals.send = { [weak channel] in channel?.send($0) }
                self.keepAwake.setSessionActive(true)
                let screen = NSScreen.main?.frame.size
                let display = DesktopDisplay(
                    width: max(1, Int(screen?.width ?? 16)),
                    height: max(1, Int(screen?.height ?? 9))
                )
                channel.send(.accepted(name: Host.current().localizedName ?? "Mac", display: display,
                                       fileFeatures: FileFeature.allCases.map(\.rawValue)))
                return
            }
            if self.terminals.handle(message) { return }
            if files.handle(message, send: { [weak self, weak channel] reply in
                guard self?.activeID == id else { return }
                channel?.send(reply)
            }) { return }
            switch message {
            case let .requestControls(windowAppPID, requestID, windowCursor, preserveWindows):
                guard self.snapshotTask == nil else { return }
                self.snapshotTask = Task { [weak self, weak channel] in
                    guard let self else { return }
                    defer { self.snapshotTask = nil }
                    var state = await self.controls.snapshot(windowAppPID: windowAppPID, requestID: requestID, windowCursor: windowCursor, preserveWindows: preserveWindows == true)
                    guard !Task.isCancelled, self.activeID == id else { return }
                    state.desktopDisplays = self.sunshine.displaySelection
                    state.desktopQuality = self.sunshine.qualityState
                    state.inputAccess = CGPreflightPostEventAccess()
                    state.screenCaptureAccess = CGPreflightScreenCaptureAccess()
                    channel?.send(.controls(state))
                }
            case let .control(request):
                guard self.controlsTask == nil else {
                    channel.send(.controlResult(MacControlResult(id: request.id, error: "Another control is finishing. Try again."))); return
                }
                self.controlsTask = Task { [weak self, weak channel] in
                    guard let self else { return }
                    defer { self.controlsTask = nil }
                    let result = await self.controls.perform(request, selectDesktopDisplay: { [weak self] displayID in
                        guard let self else { throw CancellationError() }
                        try await self.sunshine.selectDisplay(displayID)
                    }, setDesktopBitrate: { [weak self] session, kbps in
                        guard let self else { throw CancellationError() }
                        try await self.sunshine.setBitrate(session: session, kbps: kbps)
                    })
                    guard !Task.isCancelled, self.activeID == id else { return }
                    channel?.send(.controlResult(result))
                }
            case let .pairDesktop(request):
                self.desktopPairing.replace { [weak self, weak channel] in
                    guard let self else { return }
                    do {
                        try await self.sunshine.approveFromCompanion(request) { [weak self] in self?.activeID == id && !Task.isCancelled }
                    } catch {
                        if !Task.isCancelled, self.activeID == id { channel?.send(.operationError("Desktop pairing failed. " + error.localizedDescription, context: .init(.desktop, requestID: request.token))) }
                    }
                }
            case .ping: channel.send(.pong)
            default:
                channel.send(.operationError("Unsupported companion operation.", context: .init(.general)))
            }
        }
        channel.onClose = { [weak self] _ in
            watchdog.invalidate()
            files.close()
            guard let self else { return }
            self.channels[id] = nil
            if self.activeID == id { self.endSession(); self.status = self.isRunning ? "Ready for your iPhone or iPad" : "Remote access is off" }
        }
        channel.start()
    }
    private func endSession() {
        controlsTask?.cancel(); controlsTask = nil
        snapshotTask?.cancel(); snapshotTask = nil
        desktopPairing.cancel()
        sunshine.stop()
        if let activeID { admission.release(activeID) }; isConnected = false
        terminals.detach()
        keepAwake.setSessionActive(false)
    }
    private func persistLimiter() { UserDefaults.standard.set(try? JSONEncoder().encode(limiter), forKey: "attempt-limiter") }
}
