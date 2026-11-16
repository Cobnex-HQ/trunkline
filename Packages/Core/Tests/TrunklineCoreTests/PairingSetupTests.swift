import XCTest
@testable import TrunklineCore

final class PairingSetupTests: XCTestCase {
    // A QR must not advertise loopback, link-local USB, or a VPN before the active LAN.
    func testPairingAddressUsesReachablePrivateLAN() {
        XCTAssertEqual(PairingAddress.preferred(addresses: ["127.0.0.1", "169.254.50.240", "192.168.1.103"], hostname: "my-mac.local"), "192.168.1.103")
        XCTAssertEqual(PairingAddress.preferred(addresses: ["::1", "fe80::1", "169.254.1.1"], hostname: "my-mac.local"), "my-mac.local")
        XCTAssertEqual(PairingAddress.preferred(addresses: ["100.64.0.1", "10.0.0.6"], hostname: "my-mac.local"), "10.0.0.6")
        XCTAssertEqual(PairingAddress.preferred(addresses: ["172.16.1.9"], hostname: "my-mac.local"), "172.16.1.9")
    }
    // Changing from Bonjour to a LAN IP must not lose an already approved desktop certificate.
    func testDesktopTrustFollowsMacIdentityAcrossAddressChanges() throws {
        let a = try PairingDetails(host: "my-mac.local", port: 47995, fingerprint: String(repeating: "a", count: 64))
        let b = try PairingDetails(host: "192.168.1.103", port: 47995, fingerprint: String(repeating: "a", count: 64))
        let other = try PairingDetails(host: "192.168.1.103", port: 47995, fingerprint: String(repeating: "b", count: 64))
        XCTAssertEqual(DesktopTrustKey.current(a), DesktopTrustKey.current(b))
        XCTAssertNotEqual(DesktopTrustKey.current(a), DesktopTrustKey.current(other))
        XCTAssertNotEqual(DesktopTrustKey.legacy(a), DesktopTrustKey.legacy(b))
    }
    // Invalid QR codes must leave scanning active; duplicate camera frames must not navigate twice.
    func testScannerAcceptsOneValidPairingAndIgnoresOtherQRs() throws {
        var scan = PairingScan()
        XCTAssertNil(scan.accept("https://example.com"))
        XCTAssertNil(scan.accept("trunkline://pair?host=Mac&port=47995&pin=invalid"))
        let link = "trunkline://pair?host=192.168.1.103&port=47995&pin=" + String(repeating: "a", count: 64)
        XCTAssertEqual(scan.accept(link)?.host, "192.168.1.103")
        XCTAssertNil(scan.accept(link))
    }
}
