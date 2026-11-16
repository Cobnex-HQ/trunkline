import XCTest
@testable import TrunklineCore

final class SavedMacTests: XCTestCase {
    func testKeepsMultipleMacsUpdatesAddressByIdentityAndPersistsSelection() throws {
        let suite = "saved-macs-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = try PairingDetails(host: "first.local", port: 47995, fingerprint: String(repeating: "a", count: 64))
        let second = try PairingDetails(host: "second.local", port: 47995, fingerprint: String(repeating: "b", count: 64))
        var store = SavedMacStore(defaults: defaults)
        store.save(first, name: "Studio", away: false)
        store.save(second, name: "Laptop", away: true)
        let updated = try PairingDetails(host: "192.168.1.42", port: 47995, fingerprint: first.fingerprint)
        store.save(updated)
        let reloaded = SavedMacStore(defaults: defaults)
        XCTAssertEqual(reloaded.macs.count, 2)
        XCTAssertEqual(reloaded.selectedID, first.fingerprint)
        XCTAssertEqual(reloaded.macs.first { $0.id == first.fingerprint }?.name, "Studio")
        XCTAssertEqual(reloaded.macs.first { $0.id == first.fingerprint }?.link, updated.link)
        XCTAssertEqual(reloaded.macs.first { $0.id == second.fingerprint }?.away, true)
        store.remove(first.fingerprint)
        XCTAssertEqual(store.selectedID, second.fingerprint)
        XCTAssertEqual(SavedMacStore(defaults: defaults).macs.count, 1)
        XCTAssertNotEqual(SavedMac.credentialKey(first.fingerprint), SavedMac.credentialKey(second.fingerprint))
    }
    func testMigratesExistingPairingWithoutDeletingCredentialReference() throws {
        let suite = "saved-mac-migration-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let pairing = try PairingDetails(host: "studio.local", port: 47995, fingerprint: String(repeating: "c", count: 64))
        defaults.set(pairing.link, forKey: "pairing-link")
        defaults.set(pairing.link, forKey: "credential-pairing")
        defaults.set(true, forKey: "use-away-access")
        let store = SavedMacStore(defaults: defaults)
        XCTAssertEqual(store.macs.count, 1)
        XCTAssertEqual(store.selectedID, pairing.fingerprint)
        XCTAssertEqual(store.macs.first?.away, true)
        XCTAssertEqual(defaults.string(forKey: "credential-pairing"), pairing.link)
    }
}
