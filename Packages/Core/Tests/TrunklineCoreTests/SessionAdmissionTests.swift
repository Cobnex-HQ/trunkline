import XCTest
@testable import TrunklineCore
final class SessionAdmissionTests: XCTestCase {
    func testBusyMacDoesNotVerifyOrPenaliseSecondDevice() {
        var gate = SessionAdmission()
        let first = UUID(), second = UUID()
        XCTAssertEqual(gate.admit(first, verify: { true }), .accepted)
        var checks = 0
        for _ in 0..<8 {
            XCTAssertEqual(gate.admit(second, verify: { checks += 1; return false }), .busy)
        }
        XCTAssertEqual(checks, 0)
        gate.release(second)
        XCTAssertEqual(gate.owner, first)
        gate.release(first)
        XCTAssertEqual(gate.admit(second, verify: { true }), .accepted)
    }
    func testWrongPasscodeDoesNotReserveMac() {
        var gate = SessionAdmission()
        XCTAssertEqual(gate.admit(UUID(), verify: { false }), .invalidCredentials)
        XCTAssertNil(gate.owner)
        XCTAssertEqual(gate.admit(UUID(), verify: { true }), .accepted)
    }
}
