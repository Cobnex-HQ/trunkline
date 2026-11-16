import XCTest
@testable import TrunklineCore

final class StreamPerformancePolicyTests: XCTestCase {
    func testLocalHighProfilePrioritizesDetailOnTrustedWiFi() {
        XCTAssertEqual(StreamProfile.localHigh.maximumWidth, 1920)
        XCTAssertEqual(StreamProfile.localHigh.framesPerSecond, 60)
        XCTAssertEqual(StreamProfile.localHigh.bitrate, 20_000_000)
    }

    func testSmoothPacingCanBeSelectedWithoutChangingTheLatencyDefault() {
        XCTAssertFalse(StreamPacingMode.lowLatency.usesFramePacing)
        XCTAssertTrue(StreamPacingMode.smooth.usesFramePacing)
    }

    func testInputModesDescribeTheirActualPointerBehavior() {
        XCTAssertTrue(DesktopInputMode.directTouch.usesAbsolutePointer)
        XCTAssertFalse(DesktopInputMode.trackpad.usesAbsolutePointer)
    }
}
