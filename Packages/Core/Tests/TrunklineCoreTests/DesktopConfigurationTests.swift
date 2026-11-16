import XCTest
@testable import TrunklineCore

final class SunshineConfigurationTests: XCTestCase {
    // Catches config-line injection or accidentally enabling public management/UPnP.
    func testPrivateConfigurationRejectsInjectedPathsAndConfinesFiles() throws {
        XCTAssertThrowsError(try DesktopHostConfiguration(root: URL(fileURLWithPath: "/tmp/state\nupnp=on")))
        let config = try DesktopHostConfiguration(root: URL(fileURLWithPath: "/tmp/Elephant State"))
        let lines = Set(config.contents.split(separator: "\n").map(String.init))
        XCTAssertTrue(lines.contains("origin_web_ui_allowed = pc"))
        XCTAssertTrue(lines.contains("upnp = off"))
        XCTAssertTrue(lines.contains("system_tray = disabled"))
        XCTAssertTrue(lines.contains("file_state = /tmp/Elephant State/state.json"))
        XCTAssertTrue(lines.contains("lan_encryption_mode = 2"))
        XCTAssertTrue(lines.contains("wan_encryption_mode = 2"))
    }
    // Catches launching a command instead of the desktop or malformed JSON paths.
    func testDesktopApplicationDoesNotExecuteShellCommands() throws {
        let config = try DesktopHostConfiguration(root: URL(fileURLWithPath: "/tmp/state"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: config.applications) as? [String: Any])
        let apps = try XCTUnwrap(json["apps"] as? [[String: Any]])
        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps[0]["name"] as? String, "Desktop")
        XCTAssertNil(apps[0]["cmd"])
    }
    // Sunshine's util::hex reverses SHA-256 bytes and emits uppercase: plain hex fails authentication.
    func testManagementCredentialsMatchUpstreamHashFormat() throws {
        let credentials = try DesktopHostConfiguration.credentials(username: "elephant", password: "password", salt: "salt")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: credentials) as? [String: String])
        XCTAssertEqual(json["username"], "elephant")
        XCTAssertEqual(json["salt"], "salt")
        XCTAssertEqual(json["password"], "997B60F3DD238B10ECDEDC2805F9E3DCB42A5AFAC089909AC1EA18895CB8377A")
        XCTAssertFalse(String(decoding: credentials, as: UTF8.self).contains("passwordsalt"))
    }
    func testPairingApprovalRejectsMalformedPinAndRequestID() throws {
        XCTAssertThrowsError(try DesktopPairApproval(id: "abc", pin: "1234", name: "Phone"))
        XCTAssertThrowsError(try DesktopPairApproval(id: String(repeating: "a", count: 32), pin: "12\n4", name: "Phone"))
        let approval = try DesktopPairApproval(id: String(repeating: "a", count: 32), pin: "0123", name: "My iPad")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(approval)) as? [String: String])
        XCTAssertEqual(json["pairing_id"], String(repeating: "a", count: 32))
        XCTAssertEqual(json["pin"], "0123")
    }
}
