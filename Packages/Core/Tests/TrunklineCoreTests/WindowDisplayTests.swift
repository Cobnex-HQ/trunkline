import XCTest
@testable import TrunklineCore

final class WindowDisplayTests: XCTestCase {
    func testMovePreservesSizeAndRelativeCentre() throws {
        let result = try WindowPlacement.move(
            window: CGRect(x: 480, y: 270, width: 960, height: 540),
            from: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            to: CGRect(x: 1920, y: 0, width: 1280, height: 800))
        XCTAssertEqual(result, CGRect(x: 2080, y: 130, width: 960, height: 540))
    }
    func testMoveHandlesDisplaysAboveAndLeftOfPrimaryAndAvoidsMenuBar() throws {
        let result = try WindowPlacement.move(
            window: CGRect(x: -1200, y: -750, width: 800, height: 600),
            from: CGRect(x: -1600, y: -900, width: 1600, height: 900),
            to: CGRect(x: 0, y: 24, width: 1440, height: 876))
        XCTAssertEqual(result, CGRect(x: 320, y: 162, width: 800, height: 600))
    }
    func testOversizedOrOffscreenWindowsFitDestinationWorkArea() throws {
        let target = CGRect(x: 1920, y: 40, width: 1280, height: 760)
        XCTAssertEqual(try WindowPlacement.move(window: CGRect(x: -2000, y: -1000, width: 2000, height: 1200),
                                                from: CGRect(x: 0, y: 0, width: 1920, height: 1080), to: target), target)
        XCTAssertEqual(try WindowPlacement.move(window: CGRect(x: 9000, y: -9000, width: 400, height: 300),
                                                from: CGRect(x: 0, y: 0, width: 1920, height: 1080), to: target),
                       CGRect(x: 2800, y: 40, width: 400, height: 300))
    }
    func testInvalidGeometryAndDisplayIdentityAreRejected() {
        let valid = CGRect(x: 0, y: 0, width: 100, height: 100)
        for invalid in [CGRect.zero, CGRect.infinite, CGRect.null, CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10)] {
            XCTAssertThrowsError(try WindowPlacement.move(window: invalid, from: valid, to: valid))
            XCTAssertThrowsError(try WindowPlacement.move(window: valid, from: invalid, to: valid))
            XCTAssertThrowsError(try WindowPlacement.move(window: valid, from: valid, to: invalid))
        }
        XCTAssertThrowsError(try MacControlAction.moveWindow(UUID(), displayID: 0).validate())
    }
    func testMoveRequestSurvivesWireCodec() throws {
        let data = Data(#"{"control":{"_0":{"id":"11111111-1111-4111-8111-111111111111","action":{"moveWindow":{"_0":"22222222-2222-4222-8222-222222222222","displayID":74}}}}}"#.utf8)
        let request = try JSONDecoder().decode(WireMessage.self, from: data)
        var parser = PacketParser()
        let decoded = try XCTUnwrap(parser.append(PacketCodec.encode(request)).first)
        XCTAssertEqual(decoded, request)
    }
    func testWindowMoveCapabilityIsPreservedWithoutBreakingLegacyWindows() throws {
        let data = Data(#"{"id":"22222222-2222-4222-8222-222222222222","title":"Notes","minimized":false,"canMoveToDisplay":true}"#.utf8)
        let window = try JSONDecoder().decode(MacWindow.self, from: data)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(window)) as? [String: Any])
        XCTAssertEqual(object["canMoveToDisplay"] as? Bool, true)
        let legacy = Data(#"{"id":"22222222-2222-4222-8222-222222222222","title":"Notes","minimized":false}"#.utf8)
        XCTAssertNoThrow(try JSONDecoder().decode(MacWindow.self, from: legacy))
    }
}
