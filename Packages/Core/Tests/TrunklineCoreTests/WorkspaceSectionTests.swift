import XCTest
@testable import TrunklineCore

final class WorkspaceSectionTests: XCTestCase {
    func testWorkspaceSectionsExposeStableTitlesAndSymbols() {
        XCTAssertEqual(WorkspaceSection.desktop.title, "Desktop")
        XCTAssertEqual(WorkspaceSection.desktop.systemImage, "display")
        XCTAssertEqual(WorkspaceSection.terminal.title, "Terminal")
        XCTAssertEqual(WorkspaceSection.terminal.systemImage, "terminal")
    }
}
