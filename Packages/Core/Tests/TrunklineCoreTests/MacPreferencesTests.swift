import XCTest
@testable import TrunklineCore

final class MacPreferencesTests: XCTestCase {
    func testClipboardOnlySettingsMigrateWithoutLosingConsent() throws {
        let preferences = try JSONDecoder().decode(MacPreferences.self, from: Data(#"{"clipboard":"fromMac"}"#.utf8))
        XCTAssertEqual(preferences.clipboard, .fromMac)
        XCTAssertEqual(preferences.profile, .responsive)
        XCTAssertEqual(preferences.inputMode, .directTouch)
        XCTAssertTrue(preferences.adaptiveQuality)
        XCTAssertNil(preferences.displayID)
    }
    func testUnknownSettingsFallBackIndividually() throws {
        let preferences = try JSONDecoder().decode(MacPreferences.self,
            from: Data(#"{"clipboard":"fromMac","profile":"future","inputMode":"future","pacing":"future","displayID":"42"}"#.utf8))
        XCTAssertEqual(preferences.clipboard, .fromMac)
        XCTAssertEqual(preferences.profile, .responsive)
        XCTAssertEqual(preferences.pacing, .lowLatency)
        XCTAssertEqual(preferences.displayID, "42")
    }
    func testUpdatesMergeFieldsAndKeepMacsSeparate() {
        let suite = "preferences-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = MacPreferencesStore(defaults: defaults), second = MacPreferencesStore(defaults: defaults)
        first.update("a") { $0.profile = .detail; $0.displayID = "42" }
        second.update("a") { $0.clipboard = .bothDirections }
        XCTAssertEqual(first.load("a").profile, .detail)
        XCTAssertEqual(first.load("a").clipboard, .bothDirections)
        XCTAssertEqual(first.load("b"), MacPreferences())
        first.remove("a")
        XCTAssertEqual(second.load("a"), MacPreferences())
    }
    func testPersistentDisplayIdentitySurvivesChangedCaptureNumbers() throws {
        var preferences = MacPreferences(); preferences.displayID = "monitor-serial"
        let display = DesktopCaptureDisplay(id: "93", name: "External", width: 1920, height: 1080, persistentID: "monitor-serial")
        XCTAssertEqual(preferences.availableDisplay(in: [display])?.id, "93")
        let old = try JSONDecoder().decode(DesktopCaptureDisplay.self,
            from: Data(#"{"id":"42","name":"Old host display","width":1920,"height":1080}"#.utf8))
        XCTAssertNil(old.persistentID)
        let renamed = DesktopDisplaySelection(displays: [display]).withDisplayNames(["93": "Studio monitor"])
        XCTAssertEqual(renamed.displays.first?.persistentID, "monitor-serial")
    }

    func testMissingDisplayDoesNotSelectAnotherDisplayByPosition() {
        var preferences = MacPreferences()
        preferences.displayID = "42"
        let displays = [DesktopCaptureDisplay(id: "7", name: "Built-in", width: 3024, height: 1964)]
        XCTAssertNil(preferences.availableDisplay(in: displays))
        XCTAssertEqual(preferences.displayID, "42", "Keep the preference for when that display returns")
        XCTAssertEqual(preferences.availableDisplay(in: displays + [DesktopCaptureDisplay(id: "42", name: "External", width: 1920, height: 1080)])?.id, "42")
    }
}
