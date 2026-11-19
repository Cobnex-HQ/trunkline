import Foundation
import CryptoKit
import Security
import LocalAuthentication

public struct DeviceClaim: Codable, Equatable, Sendable {
    public let id: UUID
    public let secret: UUID
    public let name: String
    public init(id: UUID = UUID(), secret: UUID = UUID(), name: String) {
        self.id = id; self.secret = secret; self.name = name
    }
    var tokenHash: String { SHA256.hash(data: Data(secret.uuidString.utf8)).map { String(format: "%02x", $0) }.joined() }
}
public struct TrustedDevice: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable { case trusted, pending, revoked }
    public let id: UUID
    public var name: String
    public var lastSeen: Date
    public var status: Status
    fileprivate let tokenHash: String
}
public struct DeviceAccessPolicy: Codable, Equatable, Sendable {
    public enum Decision: Equatable { case allowed, approvalRequired, revoked, legacyBlocked }
    public private(set) var devices: [TrustedDevice] = []
    public private(set) var requiresApproval = false
    public init() {}
    public mutating func requireApproval() { requiresApproval = true }
    /// Called only after passcode validation. The plaintext claim is never persisted by the host.
    public mutating func authenticate(_ claim: DeviceClaim?) -> Decision {
        guard let claim else { return requiresApproval ? .legacyBlocked : .allowed }
        let name = String(claim.name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(80).map(String.init).joined())
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .revoked }
        if let index = devices.firstIndex(where: { $0.id == claim.id }) {
            guard devices[index].tokenHash == claim.tokenHash else { return .revoked }
            switch devices[index].status {
            case .revoked: return .revoked
            case .pending: return .approvalRequired
            case .trusted:
                devices[index].lastSeen = Date(); devices[index].name = name
                return .allowed
            }
        }
        guard devices.count < 128 else { return .approvalRequired }
        devices.append(TrustedDevice(id: claim.id, name: name, lastSeen: Date(), status: requiresApproval ? .pending : .trusted, tokenHash: claim.tokenHash))
        return requiresApproval ? .approvalRequired : .allowed
    }
    public mutating func revoke(_ id: UUID) {
        requiresApproval = true
        if let index = devices.firstIndex(where: { $0.id == id }) { devices[index].status = .revoked }
    }
    public mutating func approve(_ id: UUID) {
        if let index = devices.firstIndex(where: { $0.id == id }) { devices[index].status = .trusted }
    }
}

public enum DeviceIdentity {
    /// No authentication dialog and no new identity if Keychain is temporarily unavailable.
    public static func claim(macID: String, name: String) throws -> DeviceClaim {
        try claim(macID: macID, name: name, read: SecItemCopyMatching, add: SecItemAdd)
    }
    static func claim(macID: String, name: String,
                      read: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus,
                      add: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus) throws -> DeviceClaim {
        let context = LAContext(); context.interactionNotAllowed = true
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.trunkline.device-identity", kSecAttrAccount as String: macID,
            kSecUseAuthenticationContext as String: context, kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = read(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, let saved = try? JSONDecoder().decode(DeviceClaim.self, from: data) {
            return DeviceClaim(id: saved.id, secret: saved.secret, name: name)
        }
        guard status == errSecItemNotFound else { throw IdentityError.unavailable(status) }
        let claim = DeviceClaim(name: name)
        var item = query
        item.removeValue(forKey: kSecReturnData as String); item.removeValue(forKey: kSecMatchLimit as String)
        item[kSecValueData as String] = try JSONEncoder().encode(claim)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = add(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw IdentityError.unavailable(added) }
        return claim
    }
    private enum IdentityError: LocalizedError {
        case unavailable(OSStatus)
        var errorDescription: String? { guard case let .unavailable(code) = self else { return nil }; return "This device’s saved identity is unavailable. Unlock the device and try again. Existing credentials were preserved. (Keychain \(code))" }
    }
}

public enum DesktopPairingReset {
    public static func require(in root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data().write(to: root.appendingPathComponent("pairing-reset-required"), options: .atomic)
    }
    /// Call only after the engine and its supervisor have exited, before any new launch.
    public static func applyIfRequired(in root: URL) throws {
        let marker = root.appendingPathComponent("pairing-reset-required")
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        let state = root.appendingPathComponent("state.json")
        if FileManager.default.fileExists(atPath: state.path) {
            try cleared(Data(contentsOf: state)).write(to: state, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: state.path)
        }
        try FileManager.default.removeItem(at: marker)
    }

    /// The pinned engine reads both formats. Preserve its host ID and unrelated state.
    public static func cleared(_ data: Data) throws -> Data {
        guard var value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        if var root = value["root"] as? [String: Any] {
            root.removeValue(forKey: "devices"); root.removeValue(forKey: "named_devices")
            value["root"] = root
        } else if value["root"] != nil { throw CocoaError(.fileReadCorruptFile) }
        return try JSONSerialization.data(withJSONObject: value, options: .sortedKeys)
    }
}
