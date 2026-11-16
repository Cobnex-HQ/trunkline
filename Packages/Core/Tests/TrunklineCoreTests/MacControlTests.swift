import XCTest
@testable import TrunklineCore

final class MacControlTests: XCTestCase {
    func testDesktopDisplaySelectionUsesValidatedIdentity() throws {
        let action = try JSONDecoder().decode(MacControlAction.self, from: Data(#"{"desktopDisplay":{"_0":"74"}}"#.utf8))
        XCTAssertNoThrow(try action.validate())
        XCTAssertFalse(action.requiresConfirmation)
        for id in ["", "0", "-1", "74\n", "not-a-display", "4294967296"] {
            let data = try JSONSerialization.data(withJSONObject: ["desktopDisplay": ["_0": id]])
            let invalid = try JSONDecoder().decode(MacControlAction.self, from: data)
            XCTAssertThrowsError(try invalid.validate())
        }
        let message = WireMessage.control(MacControlRequest(action: action))
        var parser = PacketParser()
        XCTAssertEqual(try parser.append(PacketCodec.encode(message)), [message])
    }
    func testDesktopDisplayCapabilitySurvivesSnapshotEncoding() throws {
        let data = Data(#"{"apps":[],"windows":[],"displays":[],"accessibility":false,"frontmostApp":"Finder","desktopDisplays":{"status":true,"supported":true,"displays":[{"id":"74","name":"Studio Display","width":2560,"height":1440}],"active_id":"1","preferred_id":"74","switching":true}}"#.utf8)
        let snapshot = try JSONDecoder().decode(MacControlSnapshot.self, from: data)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        let capability = try XCTUnwrap(object["desktopDisplays"] as? [String: Any])
        XCTAssertEqual(capability["active_id"] as? String, "1")
        XCTAssertEqual(capability["preferred_id"] as? String, "74")
        XCTAssertEqual(capability["switching"] as? Bool, true)
    }
    func testPowerCommandsRoundTripAndRequireConfirmation() throws {
        for name in ["restart", "shutDown", "logOut"] {
            let data = try JSONSerialization.data(withJSONObject: ["power": ["_0": name]])
            let action = try JSONDecoder().decode(MacControlAction.self, from: data)
            XCTAssertTrue(action.requiresConfirmation)
            let message = WireMessage.control(MacControlRequest(action: action))
            var parser = PacketParser()
            XCTAssertEqual(try parser.append(PacketCodec.encode(message)), [message])
        }
    }
    func testPowerCapabilitySurvivesSnapshotEncoding() throws {
        let data = Data(#"{"apps":[],"windows":[],"displays":[],"accessibility":false,"frontmostApp":"Finder","power":{"actions":["restart","shutDown","logOut"],"authorizationRequired":false}}"#.utf8)
        let snapshot = try JSONDecoder().decode(MacControlSnapshot.self, from: data)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        let power = try XCTUnwrap(object["power"] as? [String: Any])
        XCTAssertEqual(power["actions"] as? [String], ["restart", "shutDown", "logOut"])
    }
    func testOldHostSnapshotDoesNotAdvertiseAudioSelection() throws {
        let data = Data(#"{"apps":[],"windows":[],"displays":[],"accessibility":false,"frontmostApp":"Finder"}"#.utf8)
        let snapshot = try JSONDecoder().decode(MacControlSnapshot.self, from: data)
        XCTAssertNil(snapshot.audioOutputs)
        XCTAssertNil(snapshot.installedApps)
        XCTAssertNil(snapshot.power)
    }
    func testFuturePowerCapabilitiesAreIgnoredByOlderClients() throws {
        let data = Data(#"{"actions":["restart","futurePowerMode"],"authorizationRequired":false}"#.utf8)
        let capability = try JSONDecoder().decode(MacPowerCapability.self, from: data)
        XCTAssertEqual(capability.availableActions, [.restart])
    }
    func testAudioOutputRequestUsesStableDeviceIdentityAndValidatesIt() throws {
        let valid = Data(#"{"audioOutput":{"_0":"BuiltInSpeakerDevice"}}"#.utf8)
        let action = try JSONDecoder().decode(MacControlAction.self, from: valid)
        XCTAssertNoThrow(try action.validate())
        XCTAssertFalse(action.requiresConfirmation)
        for uid in ["", String(repeating: "x", count: 1025), "device\ncommand"] {
            let data = try JSONSerialization.data(withJSONObject: ["audioOutput": ["_0": uid]])
            let invalid = try JSONDecoder().decode(MacControlAction.self, from: data)
            XCTAssertThrowsError(try invalid.validate())
        }
        let message = WireMessage.control(MacControlRequest(action: action))
        var parser = PacketParser()
        XCTAssertEqual(try parser.append(PacketCodec.encode(message)), [message])
    }
    func testRejectsInvalidValuesBeforeExecutingHostActions() throws {
        XCTAssertThrowsError(try MacControlAction.volume(.nan).validate())
        XCTAssertThrowsError(try MacControlAction.volume(1.1).validate())
        XCTAssertThrowsError(try MacControlAction.activateApp(-1).validate())
        XCTAssertThrowsError(try MacControlAction.launchApp("com.apple.finder; rm").validate())
        XCTAssertNoThrow(try MacControlAction.volume(0.45).validate())
        XCTAssertNoThrow(try MacControlAction.launchApp("com.apple.finder").validate())
    }
    func testDisruptiveControlsRequireExplicitConfirmation() {
        XCTAssertTrue(MacControlAction.quitApp(100).requiresConfirmation)
        XCTAssertTrue(MacControlAction.system(.sleep).requiresConfirmation)
        XCTAssertTrue(MacControlAction.system(.lock).requiresConfirmation)
        XCTAssertFalse(MacControlAction.system(.spotlight).requiresConfirmation)
        XCTAssertFalse(MacControlAction.volume(0.3).requiresConfirmation)
    }
    func testControlRequestsRoundTripThroughAuthenticatedCompanionCodec() throws {
        let action = MacControlRequest(action: .system(.missionControl))
        let message = WireMessage.control(action)
        var parser = PacketParser()
        XCTAssertEqual(try parser.append(PacketCodec.encode(message)), [message])
        XCTAssertTrue(CompanionTransportPolicy.allows(message))
        XCTAssertFalse(CompanionTransportPolicy.allows(.key(code: 1, modifiers: 0)))
    }
}
