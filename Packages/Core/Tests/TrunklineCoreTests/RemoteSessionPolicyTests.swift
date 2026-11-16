import XCTest
@testable import TrunklineCore

final class RemoteSessionPolicyTests: XCTestCase {
    func testRemoteControlKeepsTheMacDisplayAwake() {
        XCTAssertEqual(RemoteSessionPolicy.awakeMode, .systemAndDisplay)
    }

    func testTerminalTitlesRemainDistinctWithinTheSameKind() {
        XCTAssertEqual(TerminalSessionLabel.title(kind: .shell, ordinal: 1), "Terminal 1")
        XCTAssertEqual(TerminalSessionLabel.title(kind: .shell, ordinal: 2), "Terminal 2")
    }
}
