import XCTest
@testable import TrunklineCore

final class WindowSelectionTests: XCTestCase {
    private enum LegacyRequest: Codable { case requestControls }
    func testOldHostCanReadNewRequestsAndNewHostCanReadOldRequests() throws {
        let current = try JSONEncoder().encode(WireMessage.requestControls(windowAppPID: 42, requestID: UUID()))
        XCTAssertNoThrow(try JSONDecoder().decode(LegacyRequest.self, from: current))
        let old = Data(#"{"requestControls":{}}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(WireMessage.self, from: old), .requestControls())
    }
    func testWindowSelectionAndRequestIdentitySurviveWireCodec() throws {
        let data = Data(#"{"requestControls":{"windowAppPID":42,"requestID":"11111111-1111-4111-8111-111111111111"}}"#.utf8)
        let request = try JSONDecoder().decode(WireMessage.self, from: data)
        var parser = PacketParser()
        let decoded = try XCTUnwrap(parser.append(PacketCodec.encode(request)).first)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: [String: Any]])
        XCTAssertEqual(object["requestControls"]?["windowAppPID"] as? Int, 42)
        XCTAssertEqual(object["requestControls"]?["requestID"] as? String, "11111111-1111-4111-8111-111111111111")
    }
    func testSnapshotRetainsTheRequestedAppEvenAfterItCloses() throws {
        let data = Data(#"{"apps":[],"windows":[],"displays":[],"accessibility":true,"frontmostApp":"Finder","windowScope":{"requestedPID":42,"error":"App closed"},"requestID":"11111111-1111-4111-8111-111111111111"}"#.utf8)
        let state = try JSONDecoder().decode(MacControlSnapshot.self, from: data)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        let scope = try XCTUnwrap(object["windowScope"] as? [String: Any])
        XCTAssertEqual(scope["requestedPID"] as? Int, 42)
        XCTAssertEqual(scope["error"] as? String, "App closed")
        XCTAssertEqual(object["requestID"] as? String, "11111111-1111-4111-8111-111111111111")
    }
}
