import XCTest
@testable import TrunklineCore

final class FileMutationTests: XCTestCase {
    func testMutationCannotRenameSharedRootOrEscapeItsParent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try FileMutation.rename(path: "", name: "other").resolve(root: root))
        XCTAssertThrowsError(try FileMutation.rename(path: "note.txt", name: "../escape").resolve(root: root))
        XCTAssertThrowsError(try FileMutation.trash(path: "").resolve(root: root))
        XCTAssertThrowsError(try FileMutation.createFolder(parent: "../outside", name: "new").resolve(root: root))
        let plan = try FileMutation.rename(path: "note.txt", name: "renamed.txt").resolve(root: root)
        XCTAssertEqual(plan.source?.lastPathComponent, "note.txt")
        XCTAssertEqual(plan.destination?.lastPathComponent, "renamed.txt")
    }
    func testMutationRejectsSymlinkEscape() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = parent.appendingPathComponent("shared"), outside = parent.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)
        XCTAssertThrowsError(try FileMutation.trash(path: "link/private.txt").resolve(root: root))
        XCTAssertThrowsError(try FileMutation.createFolder(parent: "link", name: "new").resolve(root: root))
    }
}
