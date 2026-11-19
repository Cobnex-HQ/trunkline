import XCTest
@testable import TrunklineCore

final class ConnectionHealthTests: XCTestCase {
    func testFreshMetricsKeepTheirUnitsAndActualRoute() {
        let health = ConnectionHealth(now: 100, roundTripMS: 42, roundTripTime: 99,
            frameLoss: 0.025, videoTime: 99, videoKbps: 12000, route: .away)
        XCTAssertEqual(health.roundTripMS, 42)
        XCTAssertEqual(health.frameLossPercent, 2.5)
        XCTAssertEqual(health.videoMbps, 12)
        XCTAssertEqual(health.route, .away)
    }
    func testStaleMissingAndInvalidMetricsAreUnavailableInsteadOfZero() {
        let stale = ConnectionHealth(now: 100, roundTripMS: 0, roundTripTime: 80,
            frameLoss: 0, videoTime: 96, videoKbps: 0, route: .local)
        XCTAssertNil(stale.roundTripMS)
        XCTAssertNil(stale.frameLossPercent)
        XCTAssertNil(stale.videoMbps)
        let invalid = ConnectionHealth(now: 100, roundTripMS: -1, roundTripTime: 101,
            frameLoss: .nan, videoTime: 99, videoKbps: -1, route: .local)
        XCTAssertNil(invalid.roundTripMS)
        XCTAssertNil(invalid.frameLossPercent)
        XCTAssertNil(invalid.videoMbps)
    }
}
