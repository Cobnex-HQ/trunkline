import XCTest
@testable import TrunklineCore

final class FileHandshakeTests: XCTestCase {
    // This is the pre-capability handshake shape, as decoded by older app builds.
    private enum LegacyMessage: Codable, Equatable {
        case accepted(name: String, display: DesktopDisplay)
    }

    func testFileCapabilitiesSurviveHandshakeAndUnknownFeatures() throws {
        let payload = Data(#"{"accepted":{"name":"Mac","display":{"width":1920,"height":1080},"fileFeatures":["mutations","folderUpload","cancellation","futureFeature"]}}"#.utf8)
        let decoded = try JSONDecoder().decode(WireMessage.self, from: payload)
        let encoded = try JSONEncoder().encode(decoded)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let accepted = try XCTUnwrap(object["accepted"] as? [String: Any])
        XCTAssertEqual(accepted["fileFeatures"] as? [String], ["mutations", "folderUpload", "cancellation", "futureFeature"])
        XCTAssertEqual(try JSONDecoder().decode(LegacyMessage.self, from: encoded),
                       .accepted(name: "Mac", display: .init(width: 1920, height: 1080)))
    }

    func testOldHostHandshakeStillDecodes() throws {
        let payload = try JSONEncoder().encode(LegacyMessage.accepted(name: "Old Mac", display: .init(width: 1280, height: 720)))
        XCTAssertEqual(try JSONDecoder().decode(WireMessage.self, from: payload),
                       .accepted(name: "Old Mac", display: .init(width: 1280, height: 720)))
    }
}
