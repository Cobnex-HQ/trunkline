import XCTest
@testable import TrunklineCore

final class DesktopInputModePolicyTests: XCTestCase {
    func testTouchFirstDevicesDefaultToAbsolutePointerMapping() {
        XCTAssertTrue(DesktopInputModePolicy.defaultDirectTouch)
    }
}
