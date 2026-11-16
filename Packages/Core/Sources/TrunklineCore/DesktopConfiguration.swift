import Foundation
import CryptoKit

public struct DesktopHostConfiguration {
    public let root: URL
    public init(root: URL) throws {
        guard root.isFileURL, root.path.hasPrefix("/"),
              !root.path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0 == "#" }) else {
            throw MacPhoneError.invalidPairing
        }
        self.root = root.standardizedFileURL
    }
    public var contents: String {
        """
        sunshine_name = Trunkline
        origin_web_ui_allowed = pc
        upnp = off
        system_tray = disabled
        lan_encryption_mode = 2
        wan_encryption_mode = 2
        encoder = videotoolbox
        vt_software = disabled
        vt_realtime = enabled
        file_apps = \(root.path)/apps.json
        file_state = \(root.path)/state.json
        credentials_file = \(root.path)/management.json
        pkey = \(root.path)/credentials/key.pem
        cert = \(root.path)/credentials/cert.pem
        log_path = \(root.path)/sunshine.log
        min_log_level = 2
        """
    }
    public var applications: Data { Data(#"{"env":{},"apps":[{"name":"Desktop","image-path":"desktop.png"}]}"#.utf8) }
    /// Matches the pinned host's SHA-256 followed by util::hex's reversed uppercase byte order.
    public static func credentials(username: String, password: String, salt: String) throws -> Data {
        let digest = SHA256.hash(data: Data((password + salt).utf8)).reversed().map { String(format: "%02X", $0) }.joined()
        return try JSONSerialization.data(withJSONObject: ["username": username, "salt": salt, "password": digest])
    }
}
public struct DesktopPairApproval: Encodable {
    public let pairing_id: String
    public let pin: String
    public let name: String
    public init(id: String, pin: String, name: String) throws {
        guard id.utf8.count == 32, id.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              pin.utf8.count == 4, pin.utf8.allSatisfy({ (48...57).contains($0) }),
              (1...128).contains(name.utf8.count), !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw MacPhoneError.invalidPairing
        }
        self.pairing_id = id; self.pin = pin; self.name = name
    }
}
