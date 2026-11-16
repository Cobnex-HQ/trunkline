import Foundation
import Network
import Security
import LocalAuthentication

/// Access on the main queue. NWConnection preserves message order; cap queued bytes to
/// disconnect slow receivers rather than retaining an unbounded video backlog.
@MainActor
public final class SecureChannel {
    public var onMessage: ((WireMessage) -> Void)?
    public var onReady: (() -> Void)?
    public var onClose: ((String) -> Void)?
    private let connection: NWConnection
    private var parser = PacketParser()
    private var pendingBytes = 0
    private var closed = false
    private var timeout: DispatchWorkItem?
    public init(connection: NWConnection) { self.connection = connection }
    public convenience init(pairing: PairingDetails) {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, complete in
            let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
            guard let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate], let leaf = chain.first else { complete(false); return }
            complete(CertificatePin.fingerprint(leaf) == pairing.fingerprint)
        }, DispatchQueue.global(qos: .userInitiated))
        let tcp = NWProtocolTCP.Options(); tcp.noDelay = true
        self.init(connection: NWConnection(host: NWEndpoint.Host(pairing.host), port: NWEndpoint.Port(rawValue: pairing.port)!, using: NWParameters(tls: tls, tcp: tcp)))
    }
    public func start() {
        let timeout = DispatchWorkItem { [weak self] in self?.close("Connection timed out. Check the Mac address and network.") }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: timeout)
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
            guard let self else { return }
            switch state {
            case .ready: self.timeout?.cancel(); self.onReady?(); self.onReady = nil; self.receive()
            case let .failed(error): self.close(error.localizedDescription)
            case .cancelled: self.close("Disconnected")
            default: break
            }
            }
        }
        connection.start(queue: .main)
    }
    public func send(_ message: WireMessage) {
        guard !closed else { return }
        guard CompanionTransportPolicy.allows(message) else { close("Desktop traffic requires the desktop connection."); return }
        do {
            let data = try PacketCodec.encode(message)
            guard pendingBytes + data.count <= 8 * 1024 * 1024 else { close("Network too slow. Reconnect on a faster connection."); return }
            pendingBytes += data.count
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                MainActor.assumeIsolated {
                guard let self else { return }
                self.pendingBytes -= data.count
                if let error { self.close(error.localizedDescription) }
                }
            })
        } catch { close(error.localizedDescription) }
    }
    /// Deliver an admission error before closing, so the peer receives the reason.
    public func reject(_ reason: String) {
        guard !closed, let data = try? PacketCodec.encode(.failure(reason)) else { close(reason); return }
        onMessage = nil
        timeout?.cancel()
        let deadline = DispatchWorkItem { [weak self] in self?.close(reason) }
        timeout = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: deadline)
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in
            MainActor.assumeIsolated { self?.close(reason) }
        })
    }
    public func close(_ reason: String = "Disconnected") {
        guard !closed else { return }; closed = true
        timeout?.cancel(); timeout = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        let callback = onClose
        onClose = nil; onMessage = nil; onReady = nil
        callback?(reason)
    }
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, complete, error in
            MainActor.assumeIsolated {
            guard let self, !self.closed else { return }
            do {
                if let data { for message in try self.parser.append(data) {
                    guard CompanionTransportPolicy.allows(message) else { self.close("Desktop traffic requires the desktop connection."); return }
                    self.onMessage?(message)
                } }
                if let error { self.close(error.localizedDescription) }
                else if complete { self.close() }
                else { self.receive() }
            } catch { self.close("Invalid network data.") }
            }
        }
    }
}

public enum SecretStore {
    private static let service = "com.trunkline.credentials"
    private static let hostService = "com.trunkline.host-credentials.v2"
    private static let hostKeys: Set<String> = ["host-passcode", "identity-password", "sunshine-management-password"]
    private static func storageService(_ key: String) -> String {
        #if os(macOS)
        if hostKeys.contains(key) { return hostService }
        #endif
        return service
    }
    public static func readHostSecret(_ key: String, allowInteraction: Bool = false) throws -> Data? {
        #if os(macOS)
        if hostKeys.contains(key) {
            if let value = try readHostSecret(key, service: hostService, allowInteraction: allowInteraction) { return value }
            guard let legacy = try readHostSecret(key, service: service, allowInteraction: allowInteraction) else { return nil }
            // Recreate under this signed app's own ACL. Keep the old item as a
            // migration backup; never broaden it to other applications.
            try write(legacy, key: key)
            return legacy
        }
        #endif
        return try readHostSecret(key, service: service, allowInteraction: allowInteraction)
    }
    private static func readHostSecret(_ key: String, service: String, allowInteraction: Bool) throws -> Data? {
        let context = LAContext()
        context.interactionNotAllowed = !allowInteraction
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: key,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw NSError(domain: "TrunklineKeychain", code: Int(status), userInfo: [NSLocalizedDescriptionKey:
                "Saved credentials need approval. Click Authorize saved credentials on this Mac, then approve Trunkline in the macOS prompt."])
        }
        return result as? Data
    }
    private static func credentialError(_ status: OSStatus) -> NSError {
        NSError(domain: "TrunklineKeychain", code: Int(status), userInfo: [NSLocalizedDescriptionKey:
            "Saved credentials are unavailable. Unlock your login Keychain or use Authorize access in Trunkline on this Mac. Existing credentials have been preserved."])
    }
    public static func read(_ key: String, context: LAContext? = nil) -> Data? {
        #if os(macOS)
        if hostKeys.contains(key) { return try? readHostSecret(key) }
        #endif
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        if let context { query[kSecUseAuthenticationContext as String] = context }
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
    public static func write(_ data: Data, key: String) throws {
        try write(data, key: key, update: SecItemUpdate, add: SecItemAdd)
    }
    static func write(_ data: Data, key: String,
                      update: (CFDictionary, CFDictionary) -> OSStatus,
                      add: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus) throws {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: storageService(key), kSecAttrAccount as String: key]
        #if os(macOS)
        // Automatic creation/migration/update must never open an authentication
        // dialog. A denied operation is surfaced for explicit local setup.
        let context = LAContext(); context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        #endif
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = update(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            #if os(macOS)
            if hostKeys.contains(key) {
                var access: SecAccess?
                // nil trusted list means only the creating signed application.
                guard SecAccessCreate("Trunkline unattended access" as CFString, nil, &access) == errSecSuccess, let access else { throw MacPhoneError.cryptoFailure }
                item[kSecAttrAccess as String] = access
                item.removeValue(forKey: kSecAttrAccessible as String)
            }
            #endif
            let addStatus = add(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw credentialError(addStatus) }
        } else if status != errSecSuccess { throw credentialError(status) }
    }
    public static func contains(_ key: String) -> Bool {
        contains(key, service: storageService(key)) || (storageService(key) != service && contains(key, service: service))
    }
    private static func contains(_ key: String, service: String) -> Bool {
        let context = LAContext(); context.interactionNotAllowed = true
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: key, kSecReturnAttributes as String: true, kSecUseAuthenticationContext as String: context]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }
    public static func writeProtected(_ data: Data, key: String) throws {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(kCFAllocatorDefault, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, &error) else { throw MacPhoneError.cryptoFailure }
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: key, kSecAttrAccessControl as String: access, kSecValueData as String: data]
        delete(key)
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw MacPhoneError.cryptoFailure }
    }
    public static func delete(_ key: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key] as CFDictionary)
    }
}
