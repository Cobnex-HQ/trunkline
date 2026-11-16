import XCTest
@testable import TrunklineCore

final class AccessStartupTests: XCTestCase {
    func testTimeoutOnlyExpiresTheAttemptStillStarting() throws {
        var state = AccessStartup()
        let stalled = try XCTUnwrap(state.begin())
        XCTAssertTrue(state.timedOut(stalled))
        XCTAssertFalse(state.isStarting)
        let next = try XCTUnwrap(state.begin())
        XCTAssertFalse(state.timedOut(stalled))
        XCTAssertTrue(state.ready(next))
        XCTAssertFalse(state.timedOut(next))
        XCTAssertTrue(state.isRunning)
    }

    func testDoubleStartIsRejectedUntilListenerIsReady() throws {
        var state = AccessStartup()
        let token = try XCTUnwrap(state.begin())
        XCTAssertTrue(state.isStarting)
        XCTAssertFalse(state.isRunning)
        XCTAssertNil(state.begin())
        XCTAssertTrue(state.ready(token))
        XCTAssertFalse(state.isStarting)
        XCTAssertTrue(state.isRunning)
        XCTAssertNil(state.begin())
    }

    func testCancelledIdentityOrListenerCannotReviveStoppedAccess() throws {
        var state = AccessStartup()
        let old = try XCTUnwrap(state.begin())
        state.stop()
        XCTAssertFalse(state.accepts(old))
        XCTAssertFalse(state.ready(old))
        let current = try XCTUnwrap(state.begin())
        XCTAssertFalse(state.failed(old))
        XCTAssertTrue(state.isStarting)
        XCTAssertTrue(state.ready(current))
        XCTAssertFalse(state.failed(old))
        XCTAssertTrue(state.isRunning)
    }

    func testFailureAllowsRetryWithoutAcceptingOldCallbacks() throws {
        var state = AccessStartup()
        let failed = try XCTUnwrap(state.begin())
        XCTAssertTrue(state.failed(failed))
        XCTAssertFalse(state.isStarting)
        XCTAssertFalse(state.isRunning)
        let retry = try XCTUnwrap(state.begin())
        XCTAssertFalse(state.ready(failed))
        XCTAssertTrue(state.ready(retry))
    }
}
