import XCTest
@testable import TrunklineCore

final class MacDesktopInputTests: XCTestCase {
    func testPointerMatchesDisplayedDesktopAndIgnoresLetterbox() {
        let size = CGSize(width: 1000, height: 800)
        XCTAssertNil(MacDesktopInput.position(CGPoint(x: 500, y: 20), size: size, aspect: 2))
        XCTAssertEqual(MacDesktopInput.position(CGPoint(x: 250, y: 275), size: size, aspect: 2), CGPoint(x: 0.25, y: 0.25))
        XCTAssertEqual(MacDesktopInput.position(CGPoint(x: 500, y: 400), size: size, aspect: 2), CGPoint(x: 0.5, y: 0.5))
        XCTAssertNil(MacDesktopInput.position(CGPoint(x: CGFloat.nan, y: 1), size: size, aspect: 2))
    }
    func testNativeKeyboardMappingIncludesCommandAndNavigationKeys() {
        XCTAssertEqual(MacDesktopInput.virtualKey(0), 0x41)
        XCTAssertEqual(MacDesktopInput.virtualKey(55), 0x5B)
        XCTAssertEqual(MacDesktopInput.virtualKey(123), 0x25)
        XCTAssertEqual(MacDesktopInput.virtualKey(36), 0x0D)
        XCTAssertNil(MacDesktopInput.virtualKey(255))
    }
}
