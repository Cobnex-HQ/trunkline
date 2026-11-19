import XCTest
@testable import TrunklineCore

final class AdaptiveStreamTests: XCTestCase {
    func testLossReducesBitrateAndSustainedRecoveryRestoresIt() {
        var policy = AdaptiveStreamPolicy(maximumKbps: 8000)
        XCTAssertNil(policy.observe(loss: 0.1, sampleTime: 1, now: 1))
        XCTAssertEqual(policy.observe(loss: 0.1, sampleTime: 3, now: 3), 5600)
        for t in stride(from: 5.0, through: 23, by: 2) {
            XCTAssertNil(policy.observe(loss: 0, sampleTime: t, now: t))
        }
        XCTAssertEqual(policy.observe(loss: 0, sampleTime: 25, now: 25), 6160)
        XCTAssertEqual(policy.currentKbps, 6160)
    }
    func testStaleDuplicateInvalidAndSparseSamplesCannotRaiseQuality() {
        var policy = AdaptiveStreamPolicy(maximumKbps: 4000)
        _ = policy.observe(loss: 0.2, sampleTime: 1, now: 1)
        XCTAssertEqual(policy.observe(loss: 0.2, sampleTime: 3, now: 3), 2800)
        XCTAssertNil(policy.observe(loss: 0, sampleTime: 3, now: 3))
        XCTAssertNil(policy.observe(loss: 0, sampleTime: 4, now: 20))
        XCTAssertNil(policy.observe(loss: .nan, sampleTime: 21, now: 21))
        XCTAssertNil(policy.observe(loss: -1, sampleTime: 23, now: 23))
        XCTAssertNil(policy.observe(loss: 0, sampleTime: 100, now: 100))
        XCTAssertNil(policy.observe(loss: 0, sampleTime: 200, now: 200))
        XCTAssertEqual(policy.currentKbps, 2800)
    }
    func testFloorCeilingAndCooldownPreventRunawayChanges() {
        var policy = AdaptiveStreamPolicy(maximumKbps: 2000)
        for t in stride(from: 1.0, through: 199, by: 2) {
            _ = policy.observe(loss: 1, sampleTime: t, now: t)
        }
        XCTAssertEqual(policy.currentKbps, 1000)
        for t in stride(from: 201.0, through: 1001, by: 2) {
            _ = policy.observe(loss: 0, sampleTime: t, now: t)
        }
        XCTAssertEqual(policy.currentKbps, 2000)
    }
}
