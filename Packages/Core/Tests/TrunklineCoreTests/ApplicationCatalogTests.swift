import XCTest
@testable import TrunklineCore

final class ApplicationCatalogTests: XCTestCase {
    // A recursive scan must find utility folders without exposing nested helper apps,
    // duplicate installations, hidden apps, or bundles without a launchable identifier.
    func testDiscoversLaunchableAppsWithoutHelpersOrDuplicates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try app(root, "Utilities/Monitor.app", id: "org.example.monitor", name: "Monitor")
        try app(root, "Writer.app", id: "org.example.writer", name: "Writer")
        try app(root, "Writer.app/Contents/Helpers/Agent.app", id: "org.example.agent", name: "Agent")
        try app(root, "Duplicate.app", id: "org.example.writer", name: "Writer")
        try app(root, ".Hidden.app", id: "org.example.hidden", name: "Hidden")
        try app(root, "Invalid.app", id: "not a bundle id", name: "Invalid")
        let result = ApplicationCatalog.discover(in: [root])
        XCTAssertEqual(result.map(\.name), ["Monitor", "Writer"])
        XCTAssertEqual(Set(result.map(\.bundleID)), ["org.example.monitor", "org.example.writer"])
    }

    func testOlderHostSnapshotRemainsReadableWithoutInstalledApps() throws {
        let data = Data(#"{"apps":[],"windows":[],"displays":[],"accessibility":true,"frontmostApp":"Finder"}"#.utf8)
        let snapshot = try JSONDecoder().decode(MacControlSnapshot.self, from: data)
        XCTAssertNil(snapshot.installedApps)
    }

    func testCatalogSurvivesCompanionTransport() throws {
        let snapshot = MacControlSnapshot(apps: [], windows: [], displays: [], volume: nil, muted: nil,
            accessibility: true, frontmostApp: "Finder",
            installedApps: [MacInstalledApplication(name: "Writer", bundleID: "org.example.writer")])
        var parser = PacketParser()
        let decoded = try parser.append(PacketCodec.encode(.controls(snapshot)))
        guard case let .controls(received)? = decoded.first else { return XCTFail("Missing control snapshot") }
        XCTAssertEqual(received.installedApps?.first?.bundleID, "org.example.writer")
    }

    private func app(_ root: URL, _ path: String, id: String, name: String) throws {
        let contents = root.appendingPathComponent(path).appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id,
            "CFBundleDisplayName": name, "CFBundlePackageType": "APPL"], format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }
}
