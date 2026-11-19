import Foundation
import Combine
#if canImport(TrunklineCore)
import TrunklineCore
#endif

@MainActor
final class MacClientConnection: ObservableObject {
    enum Phase { case disconnected, connecting, authenticating, connected }
    @Published private(set) var phase: Phase = .disconnected
    @Published private(set) var name = "Mac"
    @Published private(set) var display = DesktopDisplay.fallback
    @Published var diagnostic = ConnectionDiagnostic()
    @Published private(set) var error: String?
    var onMessage: ((WireMessage) -> Void)?
    var onDisconnect: (() -> Void)?
    private var channel: SecureChannel?
    private var generation = UUID()
    private var watchdog: Task<Void, Never>?
    private var lastResponse = Date()
    private let deviceIdentity: @MainActor (String) throws -> DeviceClaim
    private let makeChannel: @MainActor (PairingDetails) -> SecureChannel
    init(deviceIdentity: @escaping @MainActor (String) throws -> DeviceClaim = { try DeviceIdentity.claim(macID: $0, name: Host.current().localizedName ?? "Mac") },
         makeChannel: @escaping @MainActor (PairingDetails) -> SecureChannel = { SecureChannel(pairing: $0) }) {
        self.makeChannel = makeChannel
        self.deviceIdentity = deviceIdentity
    }
    func connect(pairing: PairingDetails, passcode: String, route: ConnectionDiagnostic.Route = .local) {
        if phase != .disconnected { disconnect() }
        error = nil
        diagnostic.begin(route: route); diagnostic.advance(.secureConnection)
        let id = UUID()
        generation = id
        phase = .connecting
        let channel = makeChannel(pairing)
        self.channel = channel
        channel.onReady = { [weak self, weak channel] in
            guard let self, self.generation == id else { return }
            self.phase = .authenticating
            self.diagnostic.advance(.authentication)
            do {
                let device = try self.deviceIdentity(pairing.fingerprint)
                channel?.send(.authenticate(passcode: passcode, device: device))
            } catch { self.disconnect(reason: error.localizedDescription) }
        }
        channel.onMessage = { [weak self] message in
            guard let self, self.generation == id else { return }
            self.lastResponse = Date()
            switch message {
            case let .accepted(name, display, _):
                guard self.phase == .authenticating else { return }
                self.name = name
                self.display = display
                self.phase = .connected
                self.diagnostic.advance(.connected)
                self.send(.requestControls())
                self.onMessage?(message)
            case let .failure(message, cause):
                self.disconnect(reason: message); self.diagnostic.fail(cause ?? .unknown)
            default:
                guard self.phase == .connected else { return }
                self.onMessage?(message)
            }
        }
        channel.onClose = { [weak self, weak channel] reason in
            guard let self, self.generation == id else { return }
            self.diagnostic.fail(channel?.failureCause ?? .interrupted)
            self.disconnect(reason: reason)
        }
        lastResponse = Date()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard let self, self.generation == id else { return }
                if Date().timeIntervalSince(self.lastResponse) > 20 {
                    self.diagnostic.fail(self.phase == .authenticating ? .authenticationTimeout : .interrupted)
                    self.disconnect(reason: "The Mac stopped responding. Check its network and reconnect.")
                    return
                }
                self.send(.ping)
            }
        }
        channel.start()
    }
    func send(_ message: WireMessage) {
        guard phase == .connected else { return }
        channel?.send(message)
    }
    func disconnect(reason: String? = nil) {
        generation = UUID()
        watchdog?.cancel()
        watchdog = nil
        channel?.onClose = nil
        channel?.close()
        channel = nil
        phase = .disconnected
        error = reason
        onDisconnect?()
    }
}
