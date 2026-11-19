import XCTest
import Security
@testable import TrunklineCore

final class DeviceAccessTests: XCTestCase {
    func testRevokedDeviceCannotReturnAsANewIdentityOrLegacyClient() throws {
        var policy = DeviceAccessPolicy()
        let phone = DeviceClaim(name: "iPhone"), pad = DeviceClaim(name: "iPad")
        XCTAssertEqual(policy.authenticate(phone), .allowed)
        policy.revoke(phone.id)
        XCTAssertEqual(policy.authenticate(phone), .revoked)
        XCTAssertEqual(policy.authenticate(pad), .approvalRequired)
        XCTAssertEqual(policy.authenticate(nil), .legacyBlocked)
        policy.approve(pad.id)
        XCTAssertEqual(policy.authenticate(pad), .allowed)
        let saved = try JSONEncoder().encode(policy)
        XCTAssertFalse(String(decoding: saved, as: UTF8.self).contains(phone.secret.uuidString))
        var restored = try JSONDecoder().decode(DeviceAccessPolicy.self, from: saved)
        XCTAssertEqual(restored.authenticate(phone), .revoked)
        XCTAssertEqual(restored.authenticate(pad), .allowed)
    }
    func testLegacyAuthenticationRemainsDecodableInBothDirections() throws {
        enum Legacy: Codable { case authenticate(passcode: String) }
        let old = try JSONEncoder().encode(Legacy.authenticate(passcode: "test"))
        guard case let .authenticate(passcode, claim) = try JSONDecoder().decode(WireMessage.self, from: old) else { return XCTFail("Wrong message") }
        XCTAssertEqual(passcode, "test")
        XCTAssertNil(claim)
        let current = try JSONEncoder().encode(WireMessage.authenticate(passcode: "test", device: .init(name: "iPad")))
        guard case let .authenticate(decoded) = try JSONDecoder().decode(Legacy.self, from: current) else { return XCTFail("Wrong legacy message") }
        XCTAssertEqual(decoded, "test")
    }
    func testResetMarkerSurvivesCorruptStateAndClearsOnlyAfterSuccess() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try DesktopPairingReset.require(in: root)
        let state = root.appendingPathComponent("state.json")
        try Data("invalid".utf8).write(to: state)
        XCTAssertThrowsError(try DesktopPairingReset.applyIfRequired(in: root))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("pairing-reset-required").path))
        try Data(#"{"root":{"named_devices":[{}],"uniqueid":"host"}}"#.utf8).write(to: state)
        try DesktopPairingReset.applyIfRequired(in: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("pairing-reset-required").path))
        XCTAssertFalse(String(decoding: try Data(contentsOf: state), as: UTF8.self).contains("named_devices"))
    }
    func testUnavailableKeychainNeverReplacesAnIdentity() throws {
        var writes = 0
        for status in [errSecInteractionNotAllowed, errSecMissingEntitlement, errSecDecode] {
            XCTAssertThrowsError(try DeviceIdentity.claim(macID: "fixture", name: "iPad", read: { _, _ in status }, add: { _, _ in writes += 1; return errSecSuccess }))
        }
        XCTAssertEqual(writes, 0)
        let original = DeviceClaim(name: "Old name")
        let stored = try JSONEncoder().encode(original)
        let restored = try DeviceIdentity.claim(macID: "fixture", name: "New name", read: { _, result in
            result?.pointee = stored as CFData
            return errSecSuccess
        }, add: { _, _ in writes += 1; return errSecSuccess })
        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.secret, original.secret)
        XCTAssertEqual(restored.name, "New name")
        XCTAssertEqual(writes, 0)
    }
    func testSpoofedIDCannotReplaceStoredCredentialOrApprovalRequest() {
        var policy = DeviceAccessPolicy()
        let phone = DeviceClaim(name: "iPhone")
        XCTAssertEqual(policy.authenticate(phone), .allowed)
        let spoof = DeviceClaim(id: phone.id, secret: UUID(), name: "Imposter")
        XCTAssertEqual(policy.authenticate(spoof), .revoked)
        XCTAssertEqual(policy.devices.first?.name, "iPhone")
        XCTAssertEqual(policy.authenticate(phone), .allowed)
    }
    func testDesktopPairingResetRemovesBothCredentialFormatsAndKeepsIdentity() throws {
        let data = Data(#"{"root":{"uniqueid":"host-id","named_devices":[{"cert":"secret"}],"devices":[{"certs":["legacy-secret"]}]},"other":"keep"}"#.utf8)
        let cleared = try DesktopPairingReset.cleared(data)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: cleared) as? [String: Any])
        let root = try XCTUnwrap(json["root"] as? [String: Any])
        XCTAssertEqual(root["uniqueid"] as? String, "host-id")
        XCTAssertNil(root["devices"])
        XCTAssertNil(root["named_devices"])
        XCTAssertEqual(json["other"] as? String, "keep")
        XCTAssertThrowsError(try DesktopPairingReset.cleared(Data("invalid".utf8)))
    }
}
