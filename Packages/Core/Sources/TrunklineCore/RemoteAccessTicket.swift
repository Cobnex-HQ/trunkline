import Foundation

/// Contains the phone's private peer identity. Persist in Keychain, never defaults
/// or logs. The ordinary pairing link retains the original Mac certificate pin.
public struct RemoteAccessTicket: Codable, Equatable, Sendable {
    public struct Config: Codable, Equatable, Sendable {
        public let key: [UInt8]
        public let expected: String
        public init(key: [UInt8], expected: String) { self.key = key; self.expected = expected }
    }
    public let config: Config
    public let helper: String
    public init(config: Config, helper: String) { self.config = config; self.helper = helper }
    public func validate() throws {
        guard !config.key.isEmpty, config.key.count <= 128,
              (10...128).contains(config.expected.count),
              helper.count <= 2048, helper.hasPrefix("/"), helper.contains("/p2p/"),
              !helper.contains("/p2p-circuit"), !helper.contains(where: { $0.isWhitespace }) else {
            throw MacPhoneError.invalidPairing
        }
    }
    public static func storageKey(_ fingerprint: String) -> String { "remote-peer-" + fingerprint }
}
