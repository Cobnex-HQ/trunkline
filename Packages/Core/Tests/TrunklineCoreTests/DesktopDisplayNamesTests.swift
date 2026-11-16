import XCTest
@testable import TrunklineCore

final class DesktopDisplayNamesTests: XCTestCase {
    func testNamesMatchIdentitiesWithoutChangingCaptureState() {
        let original = DesktopDisplaySelection(displays: [
            .init(id: "74", name: "74", width: 2560, height: 1440),
            .init(id: "1", name: "1", width: 3024, height: 1964),
            .init(id: "unknown", name: "Remote display", width: 1920, height: 1080)
        ], activeID: "74", preferredID: "1", switching: true, error: "Waiting for capture")
        let named = original.withDisplayNames(["1": "Built-in Retina Display", "74": "Studio Display", "unknown": "   "])
        XCTAssertEqual(named.displays.map(\.name), ["Studio Display", "Built-in Retina Display", "Remote display"])
        XCTAssertEqual(named.displays.map(\.id), ["74", "1", "unknown"])
        XCTAssertEqual(named.selectedDisplay?.name, "Built-in Retina Display")
        XCTAssertEqual(named.displays.map(\.geometry), original.displays.map(\.geometry))
        XCTAssertEqual(named.activeID, "74")
        XCTAssertEqual(named.preferredID, "1")
        XCTAssertTrue(named.switching)
        XCTAssertEqual(named.error, "Waiting for capture")
        XCTAssertEqual(named.status, original.status)
        XCTAssertEqual(named.supported, original.supported)
        XCTAssertEqual(original.withDisplayNames([:]), original, "Missing metadata cannot rename or reorder a screen")
    }
}
