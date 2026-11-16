import XCTest
@testable import TrunklineCore

final class WindowPaginationTests: XCTestCase {
    func testContinuationAndPreservedWindowRefreshSurviveWireCodec() throws {
        let source = Data(#"{"requestControls":{"windowAppPID":42,"windowCursor":"11111111-1111-4111-8111-111111111111","preserveWindows":true}}"#.utf8)
        let request = try JSONDecoder().decode(WireMessage.self, from: source)
        var parser = PacketParser()
        let decoded = try XCTUnwrap(parser.append(PacketCodec.encode(request)).first)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: [String: Any]])
        XCTAssertEqual(object["requestControls"]?["windowCursor"] as? String, "11111111-1111-4111-8111-111111111111")
        XCTAssertEqual(object["requestControls"]?["preserveWindows"] as? Bool, true)
    }
    func testWindowContinuationMetadataSurvivesSnapshotRoundTrip() throws {
        let source = Data(#"{"apps":[],"windows":[],"displays":[],"accessibility":true,"frontmostApp":"Finder","windowPage":{"nextCursor":"11111111-1111-4111-8111-111111111111","totalCount":29}}"#.utf8)
        let state = try JSONDecoder().decode(MacControlSnapshot.self, from: source)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        let page = try XCTUnwrap(object["windowPage"] as? [String: Any])
        XCTAssertEqual(page["totalCount"] as? Int, 29)
        XCTAssertEqual(page["nextCursor"] as? String, "11111111-1111-4111-8111-111111111111")
    }
}
