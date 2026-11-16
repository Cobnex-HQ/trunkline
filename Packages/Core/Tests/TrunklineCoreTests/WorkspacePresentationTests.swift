import XCTest
@testable import TrunklineCore

final class WorkspacePresentationTests: XCTestCase {
    func testEachWorkspaceHasAConcisePurposeForAdaptiveNavigation() {
        XCTAssertEqual(WorkspaceSection.desktop.summary, "Control your Mac")
        XCTAssertEqual(WorkspaceSection.terminal.summary, "Keep work running")
    }
}
