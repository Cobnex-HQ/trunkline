import XCTest
@testable import TrunklineCore

final class StreamFrameRatePolicyTests: XCTestCase {
    func testResponsiveStreamKeepsIts60FPSRequestWhenThePreStreamDisplayReports30FPS() {
        XCTAssertEqual(StreamFrameRatePolicy.targetFramesPerSecond(for: .responsive, preStreamDisplayMaximum: 30), 60)
    }

    func testDataSaverKeepsIts30FPSRequest() {
        XCTAssertEqual(StreamFrameRatePolicy.targetFramesPerSecond(for: .dataSaver, preStreamDisplayMaximum: 120), 30)
    }
}
