import Foundation
import CryptoKit

public enum DesktopTrustKey {
    public static func current(_ pairing: PairingDetails) -> String { "sunshine-identity-" + pairing.fingerprint }
    public static func legacy(_ pairing: PairingDetails) -> String {
        "sunshine-cert-" + SHA256.hash(data: Data((pairing.host + pairing.fingerprint).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public enum PairingAddress {
    public static func preferred(addresses: [String], hostname: String) -> String {
        addresses.first { address in
            let parts = address.split(separator: ".").compactMap { UInt8($0) }
            guard parts.count == 4 else { return false }
            return parts[0] == 10 || (parts[0] == 192 && parts[1] == 168)
                || (parts[0] == 172 && (16...31).contains(parts[1]))
        } ?? hostname
    }
}

public struct PairingScan {
    private var completed = false
    public init() {}
    public mutating func accept(_ payload: String) -> PairingDetails? {
        guard !completed, let pairing = try? PairingDetails.parse(payload) else { return nil }
        completed = true
        return pairing
    }
}
