import XCTest
@testable import TrunklineCore

final class HostLaunchPolicyTests: XCTestCase {
    func testSavedPasscodeStartsAccessWhenTheMacAppLaunches() {
        XCTAssertTrue(HostLaunchPolicy.shouldStartAccess(hasPasscode: true))
    }

    func testMissingPasscodeLeavesAccessOffWhenTheMacAppLaunches() {
        XCTAssertFalse(HostLaunchPolicy.shouldStartAccess(hasPasscode: false))
    }
}
