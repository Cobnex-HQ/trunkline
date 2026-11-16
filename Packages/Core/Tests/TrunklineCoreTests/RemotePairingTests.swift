import XCTest
@testable import TrunklineCore
final class RemotePairingTests: XCTestCase {
    func testRemoteTicketSurvivesQRAndCanBeRemovedBeforeSavingOrdinaryLink() throws {
        let ticket = RemoteAccessTicket(config: .init(key: [1,2,3], expected: "12D3KooWpaired"), helper: "/ip4/203.0.113.1/udp/4001/quic-v1/p2p/12D3KooWhelper")
        let pairing = try PairingDetails(host: "192.168.1.2", port: 47995, fingerprint: String(repeating: "ab", count: 32), remote: ticket)
        let decoded = try PairingDetails.parse(pairing.link)
        XCTAssertEqual(decoded.remote, ticket)
        let ordinary = try PairingDetails(host: decoded.host, port: decoded.port, fingerprint: decoded.fingerprint)
        XCTAssertNil(try PairingDetails.parse(ordinary.link).remote)
        XCTAssertFalse(ordinary.link.contains("remote="))
    }
    func testMalformedRemoteTicketDoesNotSilentlyDowngradeToLAN() throws {
        let ordinary = try PairingDetails(host: "mac.local", port: 47995, fingerprint: String(repeating: "ab", count: 32))
        XCTAssertThrowsError(try PairingDetails.parse(ordinary.link + "&remote=garbage"))
        XCTAssertThrowsError(try PairingDetails.parse(ordinary.link + "&remote=" + String(repeating: "a", count: 16000)))
    }
}
