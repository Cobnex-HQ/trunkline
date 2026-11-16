import XCTest
@testable import TrunklineCore

final class DesktopStreamGeometryTests: XCTestCase {
    func testResponsiveProfilePreservesTheMacDisplayAspectRatio() {
        let size = DesktopStreamGeometry.size(
            maximumWidth: StreamProfile.responsive.maximumWidth,
            displayWidth: 3024,
            displayHeight: 1964
        )

        XCTAssertEqual(size.width, 1280)
        XCTAssertEqual(size.height, 830)
    }

    func testGeometryRoundsDownToEvenDimensionsForTheVideoEncoder() {
        let size = DesktopStreamGeometry.size(maximumWidth: 1600, displayWidth: 2560, displayHeight: 1601)

        XCTAssertEqual(size.width % 2, 0)
        XCTAssertEqual(size.height % 2, 0)
        XCTAssertEqual(size.width, 1600)
        XCTAssertEqual(size.height, 1000)
    }

    func testInvalidDisplayUsesTheSafeSixteenByNineFallback() {
        XCTAssertEqual(DesktopStreamGeometry.size(maximumWidth: 1280, displayWidth: 0, displayHeight: 0), .init(width: 1280, height: 720))
    }
}
