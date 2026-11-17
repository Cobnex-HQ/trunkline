import Foundation
import Combine
import AppKit
import TrunklineCore

@MainActor
final class MacClientModel: ObservableObject {
    let connection = MacClientConnection()
    let controls = ClientControls()
    @Published var pairingText = ""
    @Published var passcode = ""
    @Published var away = false
    @Published var error: String?
    @Published var status = ""
    @Published var preparing = false
    @Published var streaming = false
    @Published var profile: StreamProfile = .balanced
    @Published private(set) var savedMacs: [SavedMac] = []
    private var store = SavedMacStore(defaults: UserDefaults(suiteName: "com.trunkline.macclient")!)
    private var pairing: PairingDetails?
    private var remote: MacAwayConnection?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var engine: MacDesktopEngine?
    private var desktopWindow: MacDesktopWindow?
    private var streamTimeout: Task<Void, Never>?
    private var changes: AnyCancellable?
    init() {
        savedMacs = store.macs
        if let saved = savedMacs.first(where: { $0.id == store.selectedID }) { pairingText = saved.link; away = saved.away }
        connection.onDisconnect = { [weak self] in self?.stopDesktop(); self?.remote?.stop(); self?.controls.reset() }
        connection.onMessage = { [weak self] message in
            guard let self else { return }
            if case .accepted = message, let pairing = self.pairing {
                self.store.save(pairing, name: self.connection.name, away: self.away)
                self.savedMacs = self.store.macs
                self.passcode = ""
            }
            if case let .operationError(message, context) = message, context?.domain == .desktop {
                self.stopDesktop(); self.error = message
            }
            _ = self.controls.handle(message)
        }
        controls.send = { [weak self] in self?.connection.send($0) }
        changes = connection.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }
    func select(_ saved: SavedMac) {
        disconnect()
        store.select(saved.id)
        pairingText = saved.link; away = saved.away; passcode = ""
    }
    func remove(_ saved: SavedMac) {
        if pairing?.fingerprint == saved.id { disconnect() }
        store.remove(saved.id); savedMacs = store.macs
        if pairingText == saved.link { pairingText = ""; passcode = "" }
        SecretStore.delete(RemoteAccessTicket.storageKey(saved.id))
        UserDefaults.standard.removeObject(forKey: "mac-desktop-cert.\(saved.id)")
    }
    func connect(localHost: HostModel) {
        guard connection.phase == .disconnected, !preparing else { return }
        do {
            let source = try PairingDetails.parse(pairingText)
            guard !passcode.isEmpty else { error = "Enter the connection passcode set on the other Mac."; return }
            if source.fingerprint == localHost.fingerprint {
                error = "This pairing link belongs to this Mac. Copy the link from the other Mac."; return
            }
            if away && (localHost.isRunning || localHost.isStarting) {
                error = "Turn off sharing in My Mac → Sharing before starting an away connection."; return
            }
            if let ticket = source.remote { try SecretStore.write(JSONEncoder().encode(ticket), key: RemoteAccessTicket.storageKey(source.fingerprint)) }
            let local = try PairingDetails(host: source.host, port: source.port, fingerprint: source.fingerprint)
            pairing = local; pairingText = local.link
            error = nil
            let id = UUID(); generation = id
            if !away { connection.connect(pairing: local, passcode: passcode); return }
            guard let data = try SecretStore.readHostSecret(RemoteAccessTicket.storageKey(local.fingerprint)),
                  let ticket = try? JSONDecoder().decode(RemoteAccessTicket.self, from: data) else {
                error = "Enable Away access on the other Mac and paste its updated pairing link."; return
            }
            let remote = MacAwayConnection(); self.remote = remote
            remote.onLost = { [weak self] message in self?.disconnect(); self?.error = message }
            preparing = true; status = "Establishing a direct connection…"
            task = Task {
                do {
                    // Stop access may still be retiring its desktop helper.
                    // Its ports must be free before the outgoing tunnel binds.
                    await localHost.sunshine.shutdown()
                    try Task.checkCancellation()
                    try await remote.start(ticket)
                    guard self.generation == id, !Task.isCancelled else { return }
                    self.preparing = false
                    self.connection.connect(pairing: try PairingDetails(host: "127.0.0.1", port: local.port, fingerprint: local.fingerprint), passcode: self.passcode)
                } catch {
                    guard self.generation == id else { return }
                    self.disconnect(); self.error = error.localizedDescription
                }
            }
        } catch { self.error = error.localizedDescription }
    }
    func openDesktop() {
        guard connection.phase == .connected, let pairing else { return }
        if let desktopWindow { desktopWindow.open(); return }
        let engine = MacDesktopEngine()
        self.engine = engine
        error = nil; status = "Preparing desktop…"; streaming = true
        let selected = controls.snapshot?.desktopDisplays?.selectedDisplay
        let width = selected?.width ?? connection.display.width
        let height = selected?.height ?? connection.display.height
        let size = DesktopStreamGeometry.size(maximumWidth: profile.maximumWidth, displayWidth: width, displayHeight: height)
        let window = MacDesktopWindow(engine: engine, name: connection.name, size: size)
        desktopWindow = window
        window.onClose = { [weak self] in self?.stopDesktop() }
        engine.pairingCode = { [weak self, weak engine] pin in
            guard let self, let engine else { return }
            if let request = try? DesktopPairRequest(pin: pin, token: engine.pairingToken) { self.connection.send(.pairDesktop(request)) }
        }
        let certificateKey = "mac-desktop-cert.\(pairing.fingerprint)"
        engine.paired = { certificate in UserDefaults.standard.set(certificate, forKey: certificateKey) }
        engine.stateChanged = { [weak self] state, message in
            guard let self else { return }
            self.status = state
            if state == "Streaming" { self.streamTimeout?.cancel(); self.desktopWindow?.open() }
            if let message { self.stopDesktop(); self.error = message }
        }
        streamTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(45)) } catch { return }
            self?.stopDesktop(); self?.error = "The desktop did not start. Check that Desktop sharing is enabled on the other Mac."
        }
        let host = away ? "127.0.0.1" : pairing.host
        let address = host.contains(":") ? "[\(host)]:47989" : "\(host):47989"
        engine.startHost(address, certificate: UserDefaults.standard.data(forKey: certificateKey), width: Int32(size.width), height: Int32(size.height), fps: Int32(profile.framesPerSecond), bitrate: Int32(profile.bitrate/1000), away: away)
    }
    func stopDesktop() {
        streamTimeout?.cancel(); streamTimeout = nil
        desktopWindow?.onClose = nil
        desktopWindow?.close(); desktopWindow = nil
        engine?.stop(); engine = nil
        if streaming { status = "Desktop closed" }
        streaming = false
    }
    func disconnect() {
        generation = UUID(); task?.cancel(); task = nil
        remote?.stop(); remote = nil
        connection.disconnect()
        preparing = false; status = ""
    }
    func shutdown() async {
        let tunnel = remote
        disconnect()
        await withCheckedContinuation { continuation in
            MacDesktopEngine.finishStopping { continuation.resume() }
        }
        await tunnel?.shutdown()
    }
}
