import Foundation

/// Created before opening the host listener. Connection attempts never consult
/// Keychain and therefore cannot trigger local credential interaction.
public struct PreparedHostAuthentication {
    private let record: PasscodeRecord
    public init(record: Data) throws { self.record = try JSONDecoder().decode(PasscodeRecord.self, from: record) }
    public func verify(_ passcode: String) -> Bool { record.verify(passcode) }
}

/// The random name binds the authenticated companion request to one pending
/// Moonlight handshake. Never approve the first arbitrary pending client.
public struct DesktopPairRequest: Codable, Equatable, Sendable {
    public let pin: String
    public let token: String
    public var clientName: String { "Trunkline-" + token }
    public init(pin: String, token: String) throws {
        guard pin.utf8.count == 4, pin.utf8.allSatisfy({ (48...57).contains($0) }),
              let uuid = UUID(uuidString: token), uuid.uuidString == token else { throw MacPhoneError.invalidPacket }
        self.pin = pin; self.token = token
    }
    public func validate() throws { _ = try Self(pin: pin, token: token) }
    public func matchingID(in pending: [String: String]) throws -> String? {
        try validate()
        let matches = pending.filter { $0.value == clientName }.map(\.key)
        guard matches.count <= 1 else { throw MacPhoneError.invalidPacket }
        return matches.first
    }
}
